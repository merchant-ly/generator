defmodule Commanded.Generator.Source.Graph do
  @moduledoc """
  This file describes expectations on the counts of incoming and outgoing edges
  as well as expectations on the type of the sources and destinations.

  eg. `event: [:event_handler, :external_system, :process_manager, :projection]`

  An event's destination can be an event handler, external system, process
  manager or a projection.  If source shows an event's destination as directly
  connected to a command, it will issue a error.
  """
  alias Graph, as: LibGraph

  defmodule Node do
    defstruct [
      :id,
      :type,
      :name,
      :fields,
      :board,
      :position
    ]

    @type type() ::
            :aggregate
            | :command
            | :event
            | :event_handler
            | :external_system
            | :process_manager
            | :projection
            | :unknown

    @type t() :: %__MODULE__{
            type: type(),
            name: String.t(),
            fields: list(String.t()),
            board: String.t(),
            position: {number(), number()}
          }
  end

  @outs %{
    aggregate: [:event],
    command: [:aggregate],
    event: [:event, :event_handler, :external_system, :process_manager, :projection],
    event_handler: [:command, :event],
    external_system: [:command, :event],
    process_manager: [:command],
    projection: [:external_system]
  }

  @edges Enum.flat_map(@outs, fn {from, tos} -> Enum.map(tos, fn to -> {from, to} end) end)

  @vertices %{
    aggregate: %{
      expected_in: :one_or_more,
      expected_out: :one_or_more
    },
    command: %{
      expected_in: :maybe_one_or_more,
      expected_out: :only_one
    },
    event: %{
      expected_in: :only_one,
      expected_out: :maybe_one_or_more
    },
    event_handler: %{
      expected_in: :one_or_more,
      expected_out: :maybe_one_or_more
    },
    external_system: %{
      expected_in: :maybe_one_or_more,
      expected_out: :maybe_one_or_more
    },
    process_manager: %{
      expected_in: :one_or_more,
      expected_out: :one_or_more
    },
    projection: %{
      expected_in: :one_or_more,
      expected_out: :maybe_one_or_more
    }
  }

  def outgoing(g, vertex_id) do
    g
    |> LibGraph.out_neighbors(vertex_id)
    |> load_vertices(g)
  end

  def incoming(g, vertex_id) do
    g
    |> LibGraph.in_neighbors(vertex_id)
    |> load_vertices(g)
  end

  defp load_vertices(vertex_ids, g) do
    Enum.map(vertex_ids, &load_node(g, &1))
  end

  def build(graph) do
    {nodes, node_errors} =
      LibGraph.Reducers.Dfs.reduce(graph, {[], []}, fn id, {nodes, errors} ->
        node = load_node(graph, id)

        acc =
          case node.type do
            :unknown ->
              error = {:error, "#{node.name} color is not a known type, ignoring this node."}
              {nodes, [error | errors]}

            _known ->
              new_errors = check_node_degree(graph, node)
              {[node | nodes], new_errors ++ errors}
          end

        {:next, acc}
      end)

    {edge_errors, edges} =
      graph
      |> LibGraph.edges()
      |> Enum.map(&check_edge(graph, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.split_with(&is_binary/1)

    {nodes, edges, node_errors ++ edge_errors}
  end

  def load_node(g, v) do
    case LibGraph.vertex_labels(g, v) do
      [z] -> Map.put(z, :id, v)
      _ -> raise("There should be only one label.")
    end
  end

  def check_edge(graph, edge) do
    with %{type: type} = n1 when type != :unknown <- load_node(graph, edge.v1),
         %{type: type} = n2 when type != :unknown <- load_node(graph, edge.v2),
         :not_found <- Enum.find(@edges, :not_found, &(&1 == {n1.type, n2.type})) do
      "#{n1.name} -> #{n2.name} (#{n1.type} -> #{n2.type}) is not a known relationship, ignoring this edge."
    else
      %{type: :unknown} -> nil
      {_, _} = edge_type -> {edge, edge_type}
    end
  end

  def check_node_degree(graph, node) do
    rules = @vertices[node.type]

    []
    |> check_node_edges(LibGraph.out_neighbors(graph, node.id), "outgoing", rules.expected_out)
    |> check_node_edges(LibGraph.in_neighbors(graph, node.id), "incoming", rules.expected_in)
    |> Enum.map(&"#{node.name} #{&1}")
  end

  def check_node_edges(errors, [], dir, :only_one) do
    ["should have one #{dir}" | errors]
  end

  def check_node_edges(errors, list, dir, :only_one) when length(list) > 1 do
    ["should only have one #{dir} but has #{length(list)}" | errors]
  end

  def check_node_edges(errors, [], dir, :one_or_more) do
    ["should have one or more #{dir}s" | errors]
  end

  def check_node_edges(errors, _, _, _), do: errors
end

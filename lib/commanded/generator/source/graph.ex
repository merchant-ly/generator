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
  alias Commanded.Generator.Source.Miro.Graph, as: MiroGraph

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
    {node_errors, nodes} = remove_unknown_nodes(graph)

    {edge_errors, edges} = remove_invalid_edges(graph)

    parent_nodes = consolidate_parent_nodes(nodes)

    nodes = [%Node{id: -1, name: "Implied External System", type: :external_system} | nodes]

    edges =
      edges
      |> add_implicit_external_edges(nodes)
      |> relink_chained_events_to_source()

    graph =
      LibGraph.new()
      |> MiroGraph.graph_reduce(nodes, fn node, graph ->
        LibGraph.add_vertex(graph, node.id, node)
      end)
      |> MiroGraph.graph_reduce(edges, fn {edge, _}, graph ->
        LibGraph.add_edge(graph, edge.v1, edge.v2)
      end)

    {graph, parent_nodes, nodes, node_errors ++ edge_errors}
  end

  defp add_implicit_external_edges(edges, nodes) do
    implicit_edges =
      nodes
      |> Enum.filter(&(&1.type == :event))
      |> Enum.filter(fn node -> has_no_incoming?(edges, node.id) end)
      |> Enum.map(fn node -> {Graph.Edge.new(-1, node.id), {:external_system, :event}} end)

    edges ++ implicit_edges
  end

  defp has_no_incoming?(edges, id) do
    not Enum.any?(edges, fn {edge, _} -> id == edge.v2 end)
  end

  defp relink_chained_events_to_source(edges) do
    Enum.map(edges, fn
      {graph_edge, {:event, :event}} = edge ->
        {source_edge, {from_type, _}} = find_non_event_source(edge, edges)

        {%{graph_edge | v1: source_edge.v1}, {from_type, :event}}

      edge ->
        edge
    end)
  end

  defp find_non_event_source({edge, {:event, :event}}, edges) do
    # Note that if an event has two valid ins we later display an error, but we don't ignore the edge.
    # What to do in this situation is ambiguous, we just return the first the edge from a non-event .
    edges
    |> Enum.find(fn {possible_source, _} -> possible_source.v2 == edge.v1 end)
    |> find_non_event_source(edges)
  end

  defp find_non_event_source(nil, _edges) do
    raise("There should always be at least the implicit external system as a source")
  end

  defp find_non_event_source(edge, _edges) do
    edge
  end

  defp consolidate_parent_nodes(nodes) do
    nodes
    |> Enum.filter(&(&1.type not in [:command, :event]))
    |> Enum.group_by(&{&1.type, &1.name})
    |> Enum.map(fn {{type, name}, nodes} ->
      nodes
      |> Enum.reduce(%{ids: [], boards: [], fields: []}, fn curr, acc ->
        acc
        |> update_in([:ids], fn list -> [curr.id | list] end)
        |> update_in([:boards], fn list -> [curr.board | list] end)
        |> update_in([:fields], fn list ->
          if length(curr.fields) > length(list), do: curr.fields, else: list
        end)
      end)
      |> Map.put(:type, type)
      |> Map.put(:name, name)
    end)
  end

  defp remove_unknown_nodes(graph) do
    LibGraph.Reducers.Dfs.reduce(graph, {[], []}, fn id, {errors, nodes} ->
      node = load_node(graph, id)

      acc =
        case node.type do
          :unknown ->
            error = {:error, "#{node.name} color is not a known type, ignoring this node."}
            {[error | errors], nodes}

          _known ->
            if empty_name?(node.name) do
              error = {:error, "#{node.type} has no name, ignoring this node."}
              {[error | errors], nodes}
            else
              new_errors = check_node_degree(graph, node)
              {new_errors ++ errors, [node | nodes]}
            end
        end

      {:next, acc}
    end)
  end

  defp empty_name?(nil), do: true
  defp empty_name?(""), do: true
  defp empty_name?(_), do: false

  defp remove_invalid_edges(graph) do
    graph
    |> LibGraph.edges()
    |> Enum.map(&check_edge(graph, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.split_with(&is_binary/1)
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

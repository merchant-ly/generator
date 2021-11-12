defmodule Commanded.Generator.Source.Miro.Graph do
  alias Commanded.Generator.Source.Graph, as: SourceGraph
  alias Graph, as: LibGraph

  # Miro color palette
  defp to_palette("#f5f6f8"), do: :white
  defp to_palette("#d5f692"), do: :light_green
  defp to_palette("#f5d128"), do: :gold
  defp to_palette("#ff9d48"), do: :orange
  defp to_palette("#f16c7f"), do: :red
  defp to_palette("#ea94bb"), do: :pink
  defp to_palette("#ffcee0"), do: :light_pink
  defp to_palette("#a6ccf5"), do: :dull_blue
  defp to_palette("#be88c7"), do: :purple
  defp to_palette(value), do: value

  @default_types gold: :aggregate,
                 dull_blue: :command,
                 orange: :event,
                 pink: :event_handler,
                 white: :external_system,
                 purple: :process_manager,
                 light_green: :projection

  @doc """
  Given sticker and line data from Miro boards, we convert this into a libgraph graph
  """
  def build(data) do
    LibGraph.new()
    |> graph_reduce(data.vertices, fn vertex, graph ->
      LibGraph.add_vertex(graph, vertex.id, to_node(vertex))
    end)
    |> graph_reduce(data.edges, fn edge, graph ->
      LibGraph.add_edge(graph, edge.from, edge.to)
    end)
  end

  defp to_node(sticker, color_types \\ @default_types) do
    {name, fields} = parse_text(sticker.text)
    palette_color = to_palette(sticker.color)
    type = color_types[palette_color] || :unknown

    %SourceGraph.Node{
      type: type,
      name: name,
      fields: fields,
      position: sticker.position,
      board: sticker.board
    }
  end

  defp graph_reduce(g, list, function), do: Enum.reduce(list, g, function)

  defp parse_text(text) do
    parsed = Floki.parse_fragment!(text)

    {name_parts, fields} =
      Enum.reduce(parsed, {[], []}, fn
        {"p", _attrs, [text]}, {name_parts, fields} ->
          case Regex.split(~r/^[^A-Za-z]/, text) do
            [_prefix, name] ->
              # Field
              name = String.trim(name)
              field = name |> remove_spaces |> Macro.underscore() |> String.to_atom()

              {name_parts, fields ++ [%{name: name, field: field}]}

            [name] ->
              # Title
              name = name |> String.trim() |> remove_spaces()

              {name_parts ++ [name], fields}
          end

        {_tag_name, _attrs, _child_nodes}, acc ->
          acc
      end)

    name = Enum.join(name_parts)

    {name, fields}
  end

  defp remove_spaces(string), do: String.replace(string, ~r/\s/, "")
end

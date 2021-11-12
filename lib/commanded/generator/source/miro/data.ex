defmodule Commanded.Generator.Source.Miro.Data do
  alias Commanded.Generator.Source.Miro.Client

  defmodule Sticker do
    defstruct [:id, :color, :text, :position, :board]

    @type t :: %__MODULE__{
            id: String.t(),
            color: String.t(),
            text: String.t(),
            position: {number(), number()},
            board: String.t()
          }
  end

  defmodule Line do
    defstruct [:from, :to, :board]

    @type t :: %__MODULE__{
            from: String.t(),
            to: String.t(),
            board: String.t()
          }
  end

  def build(boards) do
    boards
    |> List.wrap()
    |> Enum.reduce(%{vertices: [], edges: []}, &add_board_data/2)
  end

  defp add_board_data(board, acc) do
    client = Client.new()

    # Miro limits replies to 1000 objects, which graph edges can use up relatively quickly.
    # Two requests is worse for rate-limits, but scoping to stickers or lines can get us more data.
    with {:ok, stickers} <- Client.list_all_widgets(client, board, widgetType: "sticker"),
         {:ok, lines} <- Client.list_all_widgets(client, board, widgetType: "line") do
      vertices = Enum.map(stickers, &parse_sticker(&1, board))
      edges = Enum.map(lines, &parse_line(&1, board))

      {:ok, %{vertices: vertices ++ acc.vertices, edges: edges ++ acc.edges}}
    end
  end

  defp parse_sticker(sticker, board) do
    %Sticker{
      id: id(sticker),
      position: position(sticker),
      text: text(sticker),
      color: color(sticker),
      board: board
    }
  end

  defp parse_line(line, board) do
    %Line{from: edge_start(line), to: edge_finish(line), board: board}
  end

  defp edge_start(line), do: get_in(line, ~w(startWidget id))
  defp edge_finish(line), do: get_in(line, ~w(endWidget id))
  defp color(sticker), do: get_in(sticker, ~w(style backgroundColor))
  defp text(sticker), do: get_in(sticker, ~w(text))
  defp id(sticker), do: get_in(sticker, ~w(id))
  defp position(sticker), do: {get_in(sticker, ~w(x)), get_in(sticker, ~w(y))}
end

defmodule Commanded.Generator.Sourceror do
  alias Sourceror.Zipper, as: Z

  def string_to_zipper(s) do
    s
    |> Sourceror.parse_string!()
    |> Z.zip()
  end

  def goto_main_block(z) do
    z
    |> Z.down()
    |> Z.right()
    |> Z.down()
    |> Z.down()
    |> Z.right()
    |> Z.down()
  end

  def aggregate_def(
        z,
        {:def, meta, [{:when, _meta, ok}, _]},
        map
      ) do
    aggregate_def(z, {:def, meta, ok}, map)
  end

  def aggregate_def(
        z,
        {:def, meta, [{which, _, [{:=, _, [inside, _block]}, second]}, _]},
        map
      )
      when which in [:execute, :apply] do
    aggregate_def(z, {:def, meta, [{which, nil, [inside, second]}, nil]}, map)
  end

  def aggregate_def(
        z,
        {:def, meta, [{which, _, [first, {:=, _, [inside, _block]}]}, _]},
        map
      )
      when which in [:execute, :apply] do
    aggregate_def(z, {:def, meta, [{which, nil, [first, inside]}, nil]}, map)
  end

  def aggregate_def(
        z,
        {:def, meta,
         [
           {:apply, _,
            [
              {:%, _, [{:__aliases__, _, _aggregate_name}, {:%{}, _, _}]},
              {:%, _, [{:__aliases__, _, event_name}, {:%{}, _, _}]}
            ]},
           _
         ]},
        %{commands: commands, events: events}
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    node = if is_nil(z), do: z, else: Z.node(z)

    aggregate_def(z, node, %{
      commands: commands,
      events: [{event_name, end_of_expression} | events]
    })
  end

  def aggregate_def(
        z,
        {:def, meta,
         [
           {:execute, _,
            [
              {:%, _, [{:__aliases__, _, _aggregate_name}, {:%{}, _, _}]},
              {:%, _, [{:__aliases__, _, command_name}, {:%{}, _, _}]}
            ]},
           _
         ]},
        %{commands: commands, events: events}
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    aggregate_def(z, Z.node(z), %{
      commands: [{command_name, end_of_expression} | commands],
      events: events
    })
  end

  def aggregate_def(z, _node, context) do
    # Handle nils after right/down better here and in process/proj
    if is_nil(z) do
      context
    else
      if is_nil(Z.right(z)) do
        context
      else
        z = Z.right(z)

        aggregate_def(z, Z.node(z), context)
      end
    end
  end

  def process_def(
        z,
        {:def, meta, [{:when, _meta, ok}, _]},
        map
      ) do
    process_def(z, {:def, meta, ok}, map)
  end

  def process_def(
        z,
        {:def, meta, [{which, _, [{:=, _, [inside, _]}, second]}, _]},
        map
      )
      when which in [:handle, :apply] do
    process_def(z, {:def, meta, [{which, nil, [inside, second]}, nil]}, map)
  end

  def process_def(
        z,
        {:def, meta, [{which, _, [first, {:=, _, [inside, _]}]}, _]},
        map
      )
      when which in [:handle, :apply] do
    process_def(z, {:def, meta, [{which, nil, [first, inside]}, nil]}, map)
  end

  def process_def(
        z,
        {:def, meta,
         [
           {:handle, _,
            [
              {:%, _, [{:__aliases__, _, _process_name}, {:%{}, _, _}]},
              {:%, _, [{:__aliases__, _, event_name_list}, {:%{}, _, _}]}
            ]},
           _
         ]},
        %{handles: events} = map
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    process_def(z, Z.node(z), %{map | handles: [{event_name_list, end_of_expression} | events]})
  end

  def process_def(
        z,
        {:def, meta,
         [
           {:apply, _,
            [
              {:%, _, [{:__aliases__, _, _process_name}, {:%{}, _, _}]},
              {:%, _, [{:__aliases__, _, event_name_list}, {:%{}, _, _}]}
            ]},
           _
         ]},
        %{applies: applies} = map
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    process_def(z, Z.node(z), %{
      map
      | applies: [{event_name_list, end_of_expression} | applies]
    })
  end

  def process_def(
        z,
        {:def, meta,
         [
           {:interested?, _, [{:%, _, [{:__aliases__, _, event_name_list}, {:%{}, _, _}]}]},
           _
         ]},
        %{interesteds: interesteds} = map
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    process_def(z, Z.node(z), %{
      map
      | interesteds: [{event_name_list, end_of_expression} | interesteds]
    })
  end

  def process_def(z, _node, context) do
    z = Z.right(z)

    if is_nil(z) do
      context
    else
      process_def(z, Z.node(z), context)
    end
  end

  def projection_def(
        z,
        {:project, meta, [{:=, _, [inside, _block]}, second, third]},
        map
      ) do
    projection_def(z, {:project, meta, [inside, second, third]}, map)
  end

  def projection_def(
        z,
        {:project, meta, [first, {:=, _, [inside, _block]}, third]},
        map
      ) do
    projection_def(z, {:project, meta, [first, inside, third]}, map)
  end

  def projection_def(
        z,
        {:project, meta, [first, second, {:=, _, [inside, _block]}]},
        map
      ) do
    projection_def(z, {:project, meta, [first, second, inside]}, map)
  end

  def projection_def(
        z,
        {:project, meta,
         [{:%, _, [{:__aliases__, _, event_name_list}, {:%{}, _, _}]}, _, {:fn, _, _}]},
        %{events: events}
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    projection_def(z, Z.node(z), %{events: [{event_name_list, end_of_expression} | events]})
  end

  def projection_def(z, _node, context) do
    z = Z.right(z)

    if is_nil(z) do
      context.events
    else
      projection_def(z, Z.node(z), context)
    end
  end

  def handler_def(
        z,
        {:handle, meta, [{:=, _, [inside, _block]}, second, third]},
        map
      ) do
    handler_def(z, {:handle, meta, [inside, second, third]}, map)
  end

  def handler_def(
        z,
        {:handle, meta, [first, {:=, _, [inside, _block]}, third]},
        map
      ) do
    handler_def(z, {:handle, meta, [first, inside, third]}, map)
  end

  def handler_def(
        z,
        {:handle, meta, [first, second, {:=, _, [inside, _block]}]},
        map
      ) do
    handler_def(z, {:handle, meta, [first, second, inside]}, map)
  end

  def handler_def(
        z,
        {:handle, meta,
         [{:%, _, [{:__aliases__, _, event_name_list}, {:%{}, _, _}]}, _, {:fn, _, _}]},
        %{events: events}
      ) do
    end_of_expression = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end)
    z = Z.right(z)

    handler_def(z, Z.node(z), %{events: [{event_name_list, end_of_expression} | events]})
  end

  def handler_def(z, _node, context) do
    z = Z.right(z)

    if is_nil(z) do
      context.events
    else
      handler_def(z, Z.node(z), context)
    end
  end
end

defmodule Commanded.Generator.Source.Miro do
  alias Commanded.Generator.Model

  alias Commanded.Generator.Model.{
    Aggregate,
    Command,
    Event,
    EventHandler,
    ProcessManager,
    Projection
  }

  alias Commanded.Generator.Source
  alias Commanded.Generator.Source.Graph, as: SourceGraph
  alias Commanded.Generator.Source.Miro.Data
  alias Commanded.Generator.Source.Miro.Graph, as: MiroGraph

  @behaviour Source

  def build(opts) do
    namespace = Keyword.fetch!(opts, :namespace)
    board_id = Keyword.fetch!(opts, :board_id)

    with {:ok, data} <- Data.build(board_id),
         model_graph <- MiroGraph.build(data),
         {nodes, edges, errors} <- SourceGraph.build(model_graph) do
      IO.inspect(errors, label: "errors")
      node_map = Enum.into(nodes, %{}, &{&1.id, &1})
      by_types = Enum.group_by(nodes, & &1.type)

      model =
        Model.new(namespace)
        |> include_aggregates(by_types.aggregate, node_map, edges)
        |> include_events(node_map, edges)
        |> include_event_handlers(by_types.event_handler, node_map, edges)
        |> include_process_managers(by_types.process_manager, node_map, edges)
        |> include_projections(by_types.projection, node_map, edges)

      {:ok, model}
    end
  end

  # Include aggregates and their associated commands and events.
  defp include_aggregates(
         %Model{namespace: namespace} = orig_model,
         grouped_aggregates,
         node_map,
         edges
       ) do
    edge_list = Enum.map(edges, &elem(&1, 0))

    prepped_aggs =
      grouped_aggregates
      |> Enum.group_by(& &1.name)
      |> Enum.map(fn {_name, aggregates} ->
        commands =
          Enum.flat_map(aggregates, fn aggregate ->
            Enum.filter(edge_list, fn %{v2: agg_id} ->
              agg_id == aggregate.id
            end)
            |> Enum.map(& &1.v1)
            |> Enum.map(&node_map[&1])
          end)

        events =
          Enum.flat_map(aggregates, fn aggregate ->
            Enum.filter(edge_list, fn %{v1: agg_id} ->
              agg_id == aggregate.id
            end)
            |> Enum.map(& &1.v2)
            |> Enum.map(&node_map[&1])
          end)

        [aggregate | _] = aggregates
        %{aggregate: aggregate, events: events, commands: commands}
      end)

    Enum.reduce(prepped_aggs, orig_model, fn node, model ->
      agg = node.aggregate
      agg_module = Module.concat([namespace, String.replace(agg.name, " ", "")])

      aggregate = %Aggregate{
        name: agg.name,
        module: agg_module,
        fields: []
      }

      aggregate =
        Enum.reduce(node.commands, aggregate, fn cmd, agg ->
          command = Command.new(Module.concat([agg_module, Commands]), cmd.name, cmd.fields)
          Aggregate.add_command(agg, command)
        end)

      aggregate =
        Enum.reduce(node.events, aggregate, fn evt, agg ->
          event = Event.new(Module.concat([agg_module, Events]), evt.name, evt.fields)
          Aggregate.add_event(agg, event)
        end)

      Model.add_aggregate(model, aggregate)
    end)
  end

  defp include_events(%Model{namespace: namespace} = orig_model, node_map, edges) do
    events =
      edges
      |> Enum.filter(fn
        {%{v2: _event_id}, {:external_system, :event}} -> true
        _ -> false
      end)
      |> Enum.map(fn {%{v2: event_id}, _} ->
        node = node_map[event_id]

        Event.new(Module.concat([namespace, Events]), node.name, node.fields)
      end)

    Enum.reduce(events, orig_model, fn evt, model ->
      Model.add_event(model, evt)
    end)
  end

  defp include_event_handlers(
         %Model{namespace: namespace} = orig_model,
         grouped_event_handlers,
         node_map,
         edges
       ) do
    edge_list = Enum.map(edges, &elem(&1, 0))

    prepped_event_handlers =
      grouped_event_handlers
      |> Enum.group_by(& &1.name)
      |> Enum.map(fn {_name, evt_handlers} ->
        events =
          Enum.flat_map(evt_handlers, fn evt_handler ->
            Enum.filter(edge_list, fn %{v2: evt_handler_id} ->
              evt_handler_id == evt_handler.id
            end)
            |> Enum.map(& &1.v1)
            |> Enum.map(&node_map[&1])
          end)

        [evt_handler | _] = evt_handlers
        %{event_handler: evt_handler, events: events}
      end)

    Enum.reduce(prepped_event_handlers, orig_model, fn node, model ->
      eh_node = node.event_handler
      module = Module.concat([namespace, Handlers, String.replace(eh_node.name, " ", "")])

      evt_handler = %EventHandler{
        name: eh_node.name,
        module: module
      }

      handler =
        Enum.reduce(node.events, evt_handler, fn evt, evth ->
          event = Event.new(module, evt.name, evt.fields)
          EventHandler.add_event(evth, event)
        end)

      Model.add_event_handler(model, handler)
    end)
  end

  defp include_process_managers(
         %Model{namespace: namespace} = orig_model,
         grouped_process_managers,
         node_map,
         edges
       ) do
    edge_list = Enum.map(edges, &elem(&1, 0))

    prepped_process_managers =
      grouped_process_managers
      |> Enum.group_by(& &1.name)
      |> Enum.map(fn {_name, proc_managers} ->
        events =
          Enum.flat_map(proc_managers, fn proc_manager ->
            Enum.filter(edge_list, fn %{v2: proc_manager_id} ->
              proc_manager_id == proc_manager.id
            end)
            |> Enum.map(& &1.v1)
            |> Enum.map(&node_map[&1])
          end)

        [proc_manager | _] = proc_managers
        %{process_manager: proc_manager, events: events}
      end)

    Enum.reduce(prepped_process_managers, orig_model, fn node, model ->
      eh_node = node.process_manager
      module = Module.concat([namespace, Processes, String.replace(eh_node.name, " ", "")])

      proc_manager = %ProcessManager{
        name: eh_node.name,
        module: module
      }

      handler =
        Enum.reduce(node.events, proc_manager, fn evt, evth ->
          event = Event.new(module, evt.name, evt.fields)
          ProcessManager.add_event(evth, event)
        end)

      Model.add_process_manager(model, handler)
    end)
  end

  defp include_projections(
         %Model{namespace: namespace} = orig_model,
         grouped_projections,
         node_map,
         edges
       ) do
    edge_list = Enum.map(edges, &elem(&1, 0))

    prepped_projections =
      grouped_projections
      |> Enum.group_by(& &1.name)
      |> Enum.map(fn {_name, projs} ->
        events =
          Enum.flat_map(projs, fn proj ->
            Enum.filter(edge_list, fn %{v2: proj_id} ->
              proj_id == proj.id
            end)
            |> Enum.map(& &1.v1)
            |> Enum.map(&node_map[&1])
          end)

        [proj | _] = projs
        %{projection: proj, events: events}
      end)

    Enum.reduce(prepped_projections, orig_model, fn node, model ->
      eh_node = node.projection
      module = Module.concat([namespace, String.replace(eh_node.name, " ", "")])

      proj = %Projection{
        name: eh_node.name,
        module: module
      }

      handler =
        Enum.reduce(node.events, proj, fn evt, evth ->
          event = Event.new(Module.concat([module, Events]), evt.name, evt.fields)
          Projection.add_event(evth, event)
        end)

      Model.add_projection(model, handler)
    end)
  end
end

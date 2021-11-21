defmodule Commanded.Generator.Source.Miro do
  alias Commanded.Generator.Model

  alias Commanded.Generator.Model.{
    Aggregate,
    Command,
    Event,
    EventHandler,
    Field,
    ProcessManager,
    Projection
  }

  alias Commanded.Generator.Source
  alias Commanded.Generator.Source.Graph, as: SourceGraph
  alias Commanded.Generator.Source.Miro.Data
  alias Commanded.Generator.Source.Miro.Graph, as: MiroGraph

  @behaviour Source

  defp fields(%{fields: fields}) do
    Enum.map(fields, &struct(Field, &1))
  end

  def build(opts) do
    namespace = Keyword.fetch!(opts, :namespace)
    board_id = Keyword.fetch!(opts, :board_id)

    with {:ok, data} <- Data.build(board_id),
         model_graph <- MiroGraph.build(data),
         {graph, parent_nodes, nodes, errors} <-
           SourceGraph.build(model_graph) do
      by_type =
        Map.merge(
          %{event_handler: [], events: [], aggregate: [], process_manager: [], projection: []},
          Enum.group_by(parent_nodes, & &1.type)
        )

      event_map = build_events(namespace, by_type.aggregate, graph)
      command_map = build_commands(namespace, by_type.aggregate, graph)

      bare_events =
        Enum.filter(nodes, fn node ->
          node.type == :event and not Map.has_key?(event_map, node.id)
        end)

      event_map =
        Enum.into(bare_events, event_map, fn evt ->
          {evt.id, Event.new(Module.concat([namespace, Events]), evt.name, fields(evt))}
        end)

      model =
        Model.new(namespace)
        |> include_aggregates(by_type.aggregate, event_map, command_map, graph)
        |> include_events(bare_events)
        |> include_event_handlers(by_type.event_handler, event_map, graph)
        |> include_process_managers(by_type.process_manager, event_map, graph)
        |> include_projections(by_type.projection, event_map, graph)

      {:ok, %{model: model, errors: errors}}
    end
  end

  defp build_commands(namespace, grouped_aggregates, graph) do
    Enum.reduce(grouped_aggregates, %{}, fn group, map ->
      module = Module.concat([namespace, String.replace(group.name, ~r/\s/, "")])

      commands =
        group.ids
        |> Enum.flat_map(&SourceGraph.incoming(graph, &1))
        |> Enum.uniq()

      Enum.into(commands, map, fn cmd ->
        {cmd.id, Command.new(Module.concat([module, Commands]), cmd.name, fields(cmd))}
      end)
    end)
  end

  defp build_events(namespace, grouped_aggregates, graph) do
    Enum.reduce(grouped_aggregates, %{}, fn group, map ->
      module = Module.concat([namespace, String.replace(group.name, ~r/\s/, "")])

      events =
        group.ids
        |> Enum.flat_map(&SourceGraph.outgoing(graph, &1))
        |> Enum.uniq()

      Enum.into(events, map, fn evt ->
        {evt.id, Event.new(Module.concat([module, Events]), evt.name, fields(evt))}
      end)
    end)
  end

  defp include_aggregates(
         %Model{namespace: namespace} = orig_model,
         grouped_aggregates,
         event_map,
         command_map,
         graph
       ) do
    Enum.reduce(grouped_aggregates, orig_model, fn group, model ->
      module = Module.concat([namespace, String.replace(group.name, ~r/\s/, "")])

      commands =
        group.ids
        |> Enum.flat_map(&SourceGraph.incoming(graph, &1))
        |> Enum.uniq()

      events =
        group.ids
        |> Enum.flat_map(&SourceGraph.outgoing(graph, &1))
        |> Enum.uniq()

      aggregate = %Aggregate{
        name: group.name,
        module: module,
        fields: []
      }

      aggregate =
        Enum.reduce(commands, aggregate, fn cmd, agg ->
          Aggregate.add_command(agg, command_map[cmd.id])
        end)

      aggregate =
        Enum.reduce(events, aggregate, fn evt, agg ->
          Aggregate.add_event(agg, event_map[evt.id])
        end)

      Model.add_aggregate(model, aggregate)
    end)
  end

  defp include_events(%Model{namespace: namespace} = orig_model, bare_events) do
    Enum.reduce(bare_events, orig_model, fn evt, model ->
      event = Event.new(Module.concat([namespace, Events]), evt.name, fields(evt))
      Model.add_event(model, event)
    end)
  end

  defp include_event_handlers(
         %Model{namespace: namespace} = orig_model,
         grouped_event_handlers,
         event_map,
         graph
       ) do
    Enum.reduce(grouped_event_handlers, orig_model, fn group, model ->
      module = Module.concat([namespace, Handlers, String.replace(group.name, " ", "")])

      events =
        group.ids
        |> Enum.flat_map(&SourceGraph.incoming(graph, &1))
        |> Enum.uniq()

      evt_handler = %EventHandler{
        name: group.name,
        module: module
      }

      handler =
        Enum.reduce(events, evt_handler, fn evt, eh ->
          event = event_map[evt.id]
          EventHandler.add_event(eh, event)
        end)

      Model.add_event_handler(model, handler)
    end)
  end

  %Commanded.Generator.Model{
    aggregates: [
      %Commanded.Generator.Model.Aggregate{
        commands: [
          %Commanded.Generator.Model.Command{
            fields: [],
            module: MyApp.Aggregate.Commands.CommandA,
            name: "Command A"
          },
          %Commanded.Generator.Model.Command{
            fields: [],
            module: MyApp.Aggregate.Commands.CommandB,
            name: "Command B"
          },
          %Commanded.Generator.Model.Command{
            fields: [],
            module: MyApp.Aggregate.Commands.CommandC,
            name: "Command C"
          }
        ],
        events: [
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventA,
            name: "Event A"
          },
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventB,
            name: "Event B"
          },
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventC,
            name: "Event C"
          }
        ],
        fields: [],
        module: MyApp.Aggregate,
        name: "Aggregate"
      }
    ],
    commands: [],
    event_handlers: [
      %Commanded.Generator.Model.EventHandler{
        events: [
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventA,
            name: "Event A"
          },
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventB,
            name: "Event B"
          }
        ],
        module: MyApp.Handlers.EventHandler,
        name: "Event Handler"
      }
    ],
    events: [],
    external_systems: [],
    namespace: MyApp,
    process_managers: [
      %Commanded.Generator.Model.ProcessManager{
        events: [
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventA,
            name: "Event A"
          },
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventB,
            name: "Event B"
          }
        ],
        module: MyApp.Processes.ProcessManager,
        name: "Process Manager"
      }
    ],
    projections: [
      %Commanded.Generator.Model.Projection{
        events: [
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventA,
            name: "Event A"
          },
          %Commanded.Generator.Model.Event{
            fields: [],
            module: MyApp.Aggregate.Events.EventB,
            name: "Event B"
          }
        ],
        fields: [],
        module: MyApp.Projections.Projection,
        name: "Projection"
      }
    ]
  }

  defp include_process_managers(
         %Model{namespace: namespace} = orig_model,
         grouped_process_managers,
         event_map,
         graph
       ) do
    Enum.reduce(grouped_process_managers, orig_model, fn group, model ->
      module = Module.concat([namespace, Processes, String.replace(group.name, ~r/\s/, "")])

      events =
        group.ids
        |> Enum.flat_map(&SourceGraph.incoming(graph, &1))
        |> Enum.uniq()

      process_manager = %ProcessManager{
        name: group.name,
        module: module
      }

      process_manager =
        Enum.reduce(events, process_manager, fn evt, pm ->
          event = event_map[evt.id]
          ProcessManager.add_event(pm, event)
        end)

      Model.add_process_manager(model, process_manager)
    end)
  end

  defp include_projections(
         %Model{namespace: namespace} = orig_model,
         grouped_projections,
         event_map,
         graph
       ) do
    Enum.reduce(grouped_projections, orig_model, fn group, model ->
      module = Module.concat([namespace, Projections, String.replace(group.name, " ", "")])

      events =
        group.ids
        |> Enum.flat_map(&SourceGraph.incoming(graph, &1))
        |> Enum.uniq()

      proj = %Projection{
        name: group.name,
        module: module,
        fields: fields(group)
      }

      projector =
        Enum.reduce(events, proj, fn evt, proj ->
          event = event_map[evt.id]
          Projection.add_event(proj, event)
        end)

      Model.add_projection(model, projector)
    end)
  end
end

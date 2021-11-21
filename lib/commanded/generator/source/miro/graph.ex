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
  defp to_palette(_), do: :unknown

  @default_types gold: :aggregate,
                 dull_blue: :command,
                 orange: :event,
                 pink: :event_handler,
                 white: :external_system,
                 purple: :process_manager,
                 light_green: :projection,
                 unknown: :unknown

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

  # %Commanded.Generator.Project{
  #   app: "my_app",
  #   app_mod: MyApp,
  #   app_path: "/Users/jeremyd/Projects/Merchantly/tmp/FfclmzKRi/new from Miro/my_app",
  #   base_path: "/Users/jeremyd/Projects/Merchantly/tmp/FfclmzKRi/new from Miro/my_app",
  #   binding: [
  #     elixir_version: "1.11.4",
  #     app_name: "my_app",
  #     app_module: "MyApp",
  #     root_app_name: "my_app",
  #     root_app_module: "MyApp",
  #     commanded_application_module: "MyApp.App",
  #     commanded_router_module: "MyApp.Router",
  #     commanded_github_version_tag: "v1.2",
  #     commanded_dep: "{:commanded, \"~> 1.2.0\"}",
  #     commanded_path: "deps/commanded",
  #     generators: nil,
  #     namespaced?: false,
  #     format_aliases: fnfn
  #   ],
  #   generators: [],
  #   model: %{
  #     errors: [
  #       error:
  #         "Can't delete seat if the Conference has been published color is not a known type, ignoring this node.",
  #       error:
  #         "Expire registration process after 1 minute color is not a known type, ignoring this node."
  #     ],
  #     model: %Commanded.Generator.Model{
  #       aggregates: [
  #         %Commanded.Generator.Model.Aggregate{
  #           commands: [
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Conference.Commands.CreateConference,
  #               name: "Create Conference"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Conference.Commands.CreateSeat,
  #               name: "Create Seat"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Conference.Commands.DeleteSeat,
  #               name: "Delete Seat"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Conference.Commands.PublishConference,
  #               name: "Publish Conference"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Conference.Commands.UnpublishConference,
  #               name: "Unpublish Conference"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Conference.Commands.UpdateConference,
  #               name: "Update Conference"
  #             }
  #           ],
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferenceCreated,
  #               name: "Conference Created"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferencePublished,
  #               name: "Conference Published"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferenceUnpublished,
  #               name: "Conference Unpublished"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferenceUpdated,
  #               name: "Conference Updated"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.SeatCreated,
  #               name: "Seat Created"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.SeatDeleted,
  #               name: "Seat Deleted"
  #             }
  #           ],
  #           fields: [],
  #           module: MyApp.Conference,
  #           name: "Conference"
  #         },
  #         %Commanded.Generator.Model.Aggregate{
  #           commands: [
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.AssignRegistrant,
  #               name: "Assign Registrant"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.ConfirmOrder,
  #               name: "Confirm Order"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.ExpireOrder,
  #               name: "Expire Order"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.MarkSeatsAsReserved,
  #               name: "Mark Seats As Reserved"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.RegisterToConference,
  #               name: "Register To Conference"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.RejectOrder,
  #               name: "Reject Order"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.Order.Commands.UpdateSeats,
  #               name: "Update Seats"
  #             }
  #           ],
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderConfirmed,
  #               name: "Order Confirmed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderExpired,
  #               name: "Order Expired"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderPlaced,
  #               name: "Order Placed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderRegistrantAssigned,
  #               name: "Order Registrant Assigned"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderReservationCompleted,
  #               name: "Order Reservation Completed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderTotalsCalculated,
  #               name: "Order Totals Calculated"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderUpdated,
  #               name: "Order Updated"
  #             }
  #           ],
  #           fields: [],
  #           module: MyApp.Order,
  #           name: "Order"
  #         },
  #         %Commanded.Generator.Model.Aggregate{
  #           commands: [
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Commands.AddSeats,
  #               name: "Add Seats"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Commands.CancelSeatReservation,
  #               name: "Cancel Seat Reservation"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Commands.CommitSeatReservation,
  #               name: "Commit  Seat Reservation"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Commands.MakeSeatReservation,
  #               name: "Make Seat Reservation"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Commands.RemoveSeats,
  #               name: "Remove Seats"
  #             }
  #           ],
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Events.AvailableSeatsChanged,
  #               name: "Available Seats Changed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Events.SeatsReservationCancelled,
  #               name: "Seats Reservation Cancelled"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Events.SeatsReservationCommitted,
  #               name: "Seats Reservation Committed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Events.SeatsReserved,
  #               name: "Seats Reserved"
  #             }
  #           ],
  #           fields: [],
  #           module: MyApp.SeatsAvailability,
  #           name: "Seats Availability"
  #         },
  #         %Commanded.Generator.Model.Aggregate{
  #           commands: [
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module:
  #                 MyApp.ThirdPartyProcessorPayment.Commands.CancelThirdPartyProcessorPayment,
  #               name: "Cancel Third Party Processor Payment"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module:
  #                 MyApp.ThirdPartyProcessorPayment.Commands.CompleteThirdPartyProcessorPayment,
  #               name: "Complete Third Party Processor Payment"
  #             },
  #             %Commanded.Generator.Model.Command{
  #               fields: [],
  #               module:
  #                 MyApp.ThirdPartyProcessorPayment.Commands.InitiateThirdPartyProcessorPayment,
  #               name: "Initiate Third Party Processor Payment"
  #             }
  #           ],
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.ThirdPartyProcessorPayment.Events.PaymentCompleted,
  #               name: "Payment Completed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.ThirdPartyProcessorPayment.Events.PaymentInitiated,
  #               name: "Payment Initiated"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.ThirdPartyProcessorPayment.Events.PaymentRejected,
  #               name: "Payment Rejected"
  #             }
  #           ],
  #           fields: [],
  #           module: MyApp.ThirdPartyProcessorPayment,
  #           name: "Third Party Processor Payment"
  #         }
  #       ],
  #       commands: [],
  #       event_handlers: [
  #         %Commanded.Generator.Model.EventHandler{
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderReservationCompleted,
  #               name: "Order Reservation Completed"
  #             }
  #           ],
  #           module: MyApp.Handlers.ThirdPartyPaymentHandler,
  #           name: "Third Party Payment Handler"
  #         }
  #       ],
  #       events: [],
  #       external_systems: [],
  #       namespace: MyApp,
  #       process_managers: [
  #         %Commanded.Generator.Model.ProcessManager{
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderConfirmed,
  #               name: "Order Confirmed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderPlaced,
  #               name: "Order Placed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Order.Events.OrderUpdated,
  #               name: "Order Updated"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.ThirdPartyProcessorPayment.Events.PaymentCompleted,
  #               name: "Payment Completed"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.SeatsAvailability.Events.SeatsReserved,
  #               name: "Seats Reserved"
  #             }
  #           ],
  #           module: MyApp.Processes.RegistrationProcessManager,
  #           name: "Registration Process Manager"
  #         }
  #       ],
  #       projections: [
  #         %Commanded.Generator.Model.Projection{
  #           events: [
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferenceCreated,
  #               name: "Conference Created"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferencePublished,
  #               name: "Conference Published"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferenceUnpublished,
  #               name: "Conference Unpublished"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.ConferenceUpdated,
  #               name: "Conference Updated"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.SeatCreated,
  #               name: "Seat Created"
  #             },
  #             %Commanded.Generator.Model.Event{
  #               fields: [],
  #               module: MyApp.Conference.Events.SeatDeleted,
  #               name: "Seat Deleted"
  #             }
  #           ],
  #           fields: [],
  #           module: MyApp.Projections.ConferenceSummary,
  #           name: "Conference Summary"
  #         }
  #       ]
  #     }
  #   },
  #   opts: [miro: "o9J_lJibPCc="],
  #   project_path: "/Users/jeremyd/Projects/Merchantly/tmp/FfclmzKRi/new from Miro/my_app",
  #   root_app: "my_app",
  #   root_mod: MyApp
  # }

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

  def graph_reduce(g, list, function), do: Enum.reduce(list, g, function)

  defp parse_text(text) do
    parsed = Floki.parse_fragment!(text)

    {name_parts, fields} =
      Enum.reduce(parsed, {[], []}, fn
        {"p", _attrs, [text]}, {name_parts, fields} ->
          case Regex.split(~r/^[^A-Za-z]/, text) do
            [_prefix, name] ->
              # Field
              name = String.trim(name)
              field = name |> String.replace(~r/\s/, "") |> Macro.underscore() |> String.to_atom()

              {name_parts, fields ++ [%{name: name, field: field}]}

            [name] ->
              # Title
              name = String.trim(name)

              {name_parts ++ [name], fields}
          end

        {_tag_name, _attrs, _child_nodes}, acc ->
          acc
      end)

    name = Enum.join(name_parts)

    {name, fields}
  end
end

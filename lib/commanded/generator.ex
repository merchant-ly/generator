defmodule Commanded.Generator do
  @moduledoc false
  import Mix.Generator
  import Commanded.Generator.Sourceror
  alias Sourceror.Zipper, as: Z
  alias Commanded.Generator.Project

  @commanded Path.expand("../..", __DIR__)
  @commanded_version Version.parse!(Mix.Project.config()[:version])
  @commanded_format [dispatch: 2, identify: 2, middleware: 1, router: 1]
  @commanded_ecto_projections_format [project: 2, project: 3]

  @callback prepare_project(Project.t()) :: Project.t()
  @callback generate(Project.t()) :: Project.t()

  defmacro __using__(_env) do
    quote do
      @behaviour unquote(__MODULE__)
      import Mix.Generator
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :templates, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(env) do
    root = Path.expand("../../templates", __DIR__)

    templates_ast =
      for {name, mappings} <- Module.get_attribute(env.module, :templates) do
        for {format, source, _, _} <- mappings, format != :keep do
          path = Path.join(root, source)

          cond do
            format in [:config, :prod_config, :eex] ->
              compiled = EEx.compile_file(path)

              quote do
                @external_resource unquote(path)
                @file unquote(path)
                def render(unquote(name), unquote(source), var!(assigns))
                    when is_list(var!(assigns)),
                    do: unquote(compiled)
              end

            {:eex_plus, add_sources} = format ->
              # first the regular file
              compiled = EEx.compile_file(path)

              # then the additional sources
              added =
                for {_type, short_path} <- add_sources do
                  add_path = Path.join(root, short_path)
                  add_compiled = EEx.compile_file(add_path)

                  quote do
                    @external_resource unquote(add_path)
                    @file unquote(add_path)
                    def render(unquote(name), unquote(short_path), var!(assigns))
                        when is_list(var!(assigns)),
                        do: unquote(add_compiled)
                  end
                end

              main =
                quote do
                  @external_resource unquote(path)
                  @file unquote(path)
                  def render(unquote(name), unquote(source), var!(assigns))
                      when is_list(var!(assigns)),
                      do: unquote(compiled)
                end

              [main | added]

            true ->
              quote do
                @external_resource unquote(path)
                def render(unquote(name), unquote(source), _assigns),
                  do: unquote(File.read!(path))
              end
          end
        end
      end

    quote do
      unquote(templates_ast)
      def template_files(name), do: Keyword.fetch!(@templates, name)
    end
  end

  defmacro template(name, mappings) do
    quote do
      @templates {unquote(name), unquote(mappings)}
    end
  end

  def copy_from(%Project{} = project, mod, name) when is_atom(name) do
    mapping = mod.template_files(name)

    for {format, source, project_location, target_path} <- mapping do
      target = Project.join_path(project, project_location, target_path)

      case format do
        :keep ->
          File.mkdir_p!(target)

        :text ->
          contents = mod.render(name, source, project.binding)

          contents =
            if Path.extname(target) in [".ex", ".exs"],
              do: [format_string!(contents, name), ?\n],
              else: contents

          create_file(target, contents)

        :config ->
          contents = mod.render(name, source, project.binding)
          config_inject(Path.dirname(target), Path.basename(target), contents)

        :prod_config ->
          contents = mod.render(name, source, project.binding)
          prod_only_config_inject(Path.dirname(target), Path.basename(target), contents)

        :eex ->
          contents = mod.render(name, source, project.binding)

          contents =
            if Path.extname(target) in [".ex", ".exs"],
              do: [format_string!(contents, name), ?\n],
              else: contents

          should_put_file? =
            not (source =~ "create_projection_versions") ||
              project.binding[:projection_versions_migration_timestamp]

          if should_put_file? && overwrite?(target, contents) do
            create_file(target, contents, force: true)
          else
            log(:blue, :ignoring, Path.relative_to_cwd(target), project.opts)
          end

        {:eex_plus, add_files} ->
          case File.read(target) do
            {:ok, target_str} ->
              case name do
                :aggregate ->
                  {missing_events, extra_events, events_end_of_expression} =
                    compare_events(project, target_str, &aggregate_def/3, :events)

                  {missing_commands, extra_commands, commands_end_of_expression} =
                    compare_commands(project, target_str, &aggregate_def/3, :commands)

                  any_events_missing? = not Enum.empty?(missing_events)
                  any_events_extra? = not Enum.empty?(extra_events)

                  any_commands_missing? = not Enum.empty?(missing_commands)
                  any_commands_extra? = not Enum.empty?(extra_commands)

                  event_patches =
                    if any_events_missing? do
                      missing_str = Enum.join(missing_events, ", ")

                      log(
                        :yellow,
                        "appending missing events",
                        "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                        project.opts
                      )

                      # Problematic if someone has manually deleted _all_ of the events
                      line = events_end_of_expression[:line] + 1

                      patch_events(
                        project.binding,
                        mod,
                        missing_events,
                        name,
                        add_files.event,
                        line
                      )
                    else
                      []
                    end

                  command_patches =
                    if any_commands_missing? do
                      missing_str = Enum.join(missing_commands, ", ")

                      log(
                        :yellow,
                        "appending missing commands",
                        "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                        project.opts
                      )

                      # Problematic if someone has manually deleted _all_ of the commands
                      line = commands_end_of_expression[:line] + 1

                      patch_commands(
                        project.binding,
                        mod,
                        missing_commands,
                        name,
                        add_files.command,
                        line
                      )
                    else
                      []
                    end

                  patches = event_patches ++ command_patches

                  # finally apply all patches
                  if not Enum.empty?(patches) do
                    final_contents = Sourceror.patch_string(target_str, patches)

                    create_file(target, [format_string!(final_contents, name), ?\n], force: true)
                  end

                  if any_commands_extra? do
                    extra_str = Enum.join(extra_commands, ",")

                    log(
                      :red,
                      "extraneous commands",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  if any_events_extra? do
                    extra_str = Enum.join(extra_events, ",")

                    log(
                      :red,
                      "extraneous events",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  if not any_commands_extra? and not any_events_extra? and
                       not any_commands_missing? and not any_events_missing? do
                    log(:blue, :ignoring, Path.relative_to_cwd(target), project.opts)
                  end

                :process_manager ->
                  z =
                    target_str
                    |> string_to_zipper
                    |> goto_main_block

                  extant_map =
                    process_def(z, Z.node(z), %{handles: [], applies: [], interesteds: []})

                  desired_events =
                    project.binding
                    |> Keyword.get(:events)
                    |> Enum.map(& &1[:module])

                  # interesteds
                  extant_interesteds =
                    extant_map.interesteds
                    |> Enum.map(fn {list, _b} -> List.last(list) end)
                    |> Enum.map(&Atom.to_string/1)

                  end_of_expression =
                    extant_map.interesteds
                    |> Enum.map(&elem(&1, 1))
                    |> Enum.sort_by(& &1[:line])
                    |> List.last()

                  missing_events = desired_events -- extant_interesteds
                  extra_events = extant_interesteds -- desired_events

                  any_missing? = not Enum.empty?(missing_events)
                  any_extra? = not Enum.empty?(extra_events)

                  interested_patches =
                    if any_missing? do
                      missing_str = Enum.join(missing_events, ", ")

                      log(
                        :yellow,
                        "appending missing interesteds",
                        "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                        project.opts
                      )

                      # Problematic if someone has manually deleted _all_ of the events
                      line = end_of_expression[:line] + 1

                      project.binding[:events]
                      |> Enum.filter(&(&1.module in missing_events))
                      |> Enum.map(fn event ->
                        contents =
                          mod.render(
                            name,
                            add_files.interested,
                            Keyword.merge(project.binding, event: event)
                          )

                        %{
                          change: [format_string!(contents, name), ?\n] |> IO.iodata_to_binary(),
                          range: %{start: [line: line, column: 1], end: [line: line, column: 1]}
                        }
                      end)
                    else
                      []
                    end

                  if any_extra? do
                    extra_str = Enum.join(extra_events, ",")

                    log(
                      :red,
                      "extraneous interesteds",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  # applies
                  extant_applies =
                    extant_map.applies
                    |> Enum.map(fn {list, _b} -> List.last(list) end)
                    |> Enum.map(&Atom.to_string/1)

                  end_of_expression =
                    extant_map.applies
                    |> Enum.map(&elem(&1, 1))
                    |> Enum.sort_by(& &1[:line])
                    |> List.last()

                  missing_events = desired_events -- extant_applies
                  extra_events = extant_applies -- desired_events

                  any_missing? = not Enum.empty?(missing_events)
                  any_extra? = not Enum.empty?(extra_events)

                  apply_patches =
                    if any_missing? do
                      missing_str = Enum.join(missing_events, ", ")

                      log(
                        :yellow,
                        "appending missing applies",
                        "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                        project.opts
                      )

                      # Problematic if someone has manually deleted _all_ of the events
                      line = end_of_expression[:line] + 1

                      project.binding[:events]
                      |> Enum.filter(&(&1.module in missing_events))
                      |> Enum.map(fn event ->
                        contents =
                          mod.render(
                            name,
                            add_files.apply,
                            Keyword.merge(project.binding, event: event)
                          )

                        %{
                          change: [format_string!(contents, name), ?\n] |> IO.iodata_to_binary(),
                          range: %{start: [line: line, column: 1], end: [line: line, column: 1]}
                        }
                      end)
                    else
                      []
                    end

                  if any_extra? do
                    extra_str = Enum.join(extra_events, ",")

                    log(
                      :red,
                      "extraneous applies",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  # handles
                  extant_handles =
                    extant_map.handles
                    |> Enum.map(fn {list, _b} -> List.last(list) end)
                    |> Enum.map(&Atom.to_string/1)

                  end_of_expression =
                    extant_map.handles
                    |> Enum.map(&elem(&1, 1))
                    |> Enum.sort_by(& &1[:line])
                    |> List.last()

                  missing_events = desired_events -- extant_handles
                  extra_events = extant_handles -- desired_events

                  any_missing? = not Enum.empty?(missing_events)
                  any_extra? = not Enum.empty?(extra_events)

                  handle_patches =
                    if any_missing? do
                      missing_str = Enum.join(missing_events, ", ")

                      log(
                        :yellow,
                        "appending missing handles",
                        "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                        project.opts
                      )

                      # Problematic if someone has manually deleted _all_ of the events
                      line = end_of_expression[:line] + 1

                      project.binding[:events]
                      |> Enum.filter(&(&1.module in missing_events))
                      |> Enum.map(fn event ->
                        contents =
                          mod.render(
                            name,
                            add_files.handle,
                            Keyword.merge(project.binding, event: event)
                          )

                        %{
                          change: [format_string!(contents, name), ?\n] |> IO.iodata_to_binary(),
                          range: %{start: [line: line, column: 1], end: [line: line, column: 1]}
                        }
                      end)
                    else
                      []
                    end

                  if any_extra? do
                    extra_str = Enum.join(extra_events, ",")

                    log(
                      :red,
                      "extraneous handles",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  patches = interested_patches ++ handle_patches ++ apply_patches

                  # finally apply all patches
                  if Enum.empty?(patches) do
                    log(:blue, :ignoring, Path.relative_to_cwd(target), project.opts)
                  else
                    final_contents = Sourceror.patch_string(target_str, patches)

                    create_file(target, [format_string!(final_contents, name), ?\n], force: true)
                  end

                :projection ->
                  {missing_events, extra_events, end_of_expression} =
                    compare_events(project, target_str, &projection_def/3)

                  any_missing? = not Enum.empty?(missing_events)
                  any_extra? = not Enum.empty?(extra_events)

                  if any_missing? do
                    missing_str = Enum.join(missing_events, ", ")

                    log(
                      :yellow,
                      "appending missing events",
                      "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                      project.opts
                    )

                    # Problematic if someone has manually deleted _all_ of the events
                    line = end_of_expression[:line] + 1

                    patches =
                      patch_events(
                        project.binding,
                        mod,
                        missing_events,
                        name,
                        add_files.event,
                        line
                      )

                    final_contents = Sourceror.patch_string(target_str, patches)

                    create_file(target, [format_string!(final_contents, name), ?\n], force: true)
                  end

                  if any_extra? do
                    extra_str = Enum.join(extra_events, ",")

                    log(
                      :red,
                      "extraneous events",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  if not any_extra? and not any_missing? do
                    log(:blue, :ignoring, Path.relative_to_cwd(target), project.opts)
                  end

                :event_handler ->
                  {missing_events, extra_events, end_of_expression} =
                    compare_events(project, target_str, &handler_def/3)

                  any_missing? = not Enum.empty?(missing_events)
                  any_extra? = not Enum.empty?(extra_events)

                  if any_missing? do
                    missing_str = Enum.join(missing_events, ", ")

                    log(
                      :yellow,
                      "appending missing events",
                      "[#{missing_str}] to #{Path.relative_to_cwd(target)}",
                      project.opts
                    )

                    # Problematic if someone has manually deleted _all_ of the events
                    line = end_of_expression[:line] + 1

                    patches =
                      patch_events(
                        project.binding,
                        mod,
                        missing_events,
                        name,
                        add_files.event,
                        line
                      )

                    final_contents = Sourceror.patch_string(target_str, patches)

                    create_file(target, [format_string!(final_contents, name), ?\n], force: true)
                  end

                  if any_extra? do
                    extra_str = Enum.join(extra_events, ",")

                    log(
                      :red,
                      "extraneous events",
                      "[#{extra_str}] in #{Path.relative_to_cwd(target)}",
                      project.opts
                    )
                  end

                  if not any_extra? and not any_missing? do
                    log(:blue, :ignoring, Path.relative_to_cwd(target), project.opts)
                  end
              end

            _read_failed ->
              contents = mod.render(name, source, project.binding)

              contents =
                if Path.extname(target) in [".ex", ".exs"],
                  do: [format_string!(contents, name), ?\n],
                  else: contents

              create_file(target, contents)
          end
      end
    end
  end

  defp compare_events(project, target_str, def_fn, map_key \\ nil) do
    {extant_events, end_of_expression} = parse_for_events(target_str, def_fn, map_key)

    desired_events =
      project.binding
      |> Keyword.get(:events)
      |> Enum.map(& &1[:module])

    missing_events = desired_events -- extant_events
    extra_events = extant_events -- desired_events

    {missing_events, extra_events, end_of_expression}
  end

  defp compare_commands(project, target_str, def_fn, map_key \\ nil) do
    {extant_commands, end_of_expression} = parse_for_commands(target_str, def_fn, map_key)

    desired_commands =
      project.binding
      |> Keyword.get(:commands)
      |> Enum.map(& &1[:module])

    missing_commands = desired_commands -- extant_commands
    extra_commands = extant_commands -- desired_commands

    {missing_commands, extra_commands, end_of_expression}
  end

  defp patch_events(project_binding, mod, add_events, name, add_file, line) do
    project_binding[:events]
    |> Enum.filter(&(&1.module in add_events))
    |> Enum.map(fn event ->
      contents = mod.render(name, add_file, Keyword.merge(project_binding, event: event))

      %{
        change: [format_string!(contents, name), ?\n] |> IO.iodata_to_binary(),
        range: %{start: [line: line, column: 1], end: [line: line, column: 1]}
      }
    end)
  end

  defp patch_commands(project_binding, mod, add_commands, name, add_file, line) do
    project_binding[:commands]
    |> Enum.filter(&(&1.module in add_commands))
    |> Enum.map(fn command ->
      contents = mod.render(name, add_file, Keyword.merge(project_binding, command: command))

      %{
        change: [format_string!(contents, name), ?\n] |> IO.iodata_to_binary(),
        range: %{start: [line: line, column: 1], end: [line: line, column: 1]}
      }
    end)
  end

  defp parse_for_events(target_str, def_fn, map_key \\ nil) do
    z =
      target_str
      |> string_to_zipper
      |> goto_main_block

    extant_tuples = def_fn.(z, Z.node(z), %{commands: [], events: []})

    extant_tuples = if is_nil(map_key), do: extant_tuples, else: extant_tuples[map_key]

    extant_events =
      extant_tuples
      |> Enum.map(fn {list, _b} -> List.last(list) end)
      |> Enum.map(&Atom.to_string/1)

    end_of_expression =
      extant_tuples
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(& &1[:line])
      |> List.last()

    {extant_events, end_of_expression}
  end

  defp parse_for_commands(target_str, def_fn, map_key \\ nil) do
    z =
      target_str
      |> string_to_zipper
      |> goto_main_block

    extant_tuples = def_fn.(z, Z.node(z), %{commands: [], events: []})

    extant_tuples = if is_nil(map_key), do: extant_tuples, else: extant_tuples[map_key]

    extant_commands =
      extant_tuples
      |> Enum.map(fn {list, _b} -> List.last(list) end)
      |> Enum.map(&Atom.to_string/1)

    end_of_expression =
      extant_tuples
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(& &1[:line])
      |> List.last()

    {extant_commands, end_of_expression}
  end

  defp log(color, command, message, opts) do
    unless opts[:quiet] do
      Mix.shell().info([color, "* #{command} ", :reset, message])
    end
  end

  defp format_string!(contents, name) do
    locals_without_parens =
      case name do
        :projection -> @commanded_ecto_projections_format
        _ -> @commanded_format
      end

    Code.format_string!(contents, locals_without_parens: locals_without_parens)
  end

  def config_inject(path, file, to_inject) do
    file = Path.join(path, file)

    contents =
      case File.read(file) do
        {:ok, bin} -> bin
        {:error, _} -> "import Config\n"
      end

    with :error <- split_with_self(contents, "use Mix.Config\n"),
         :error <- split_with_self(contents, "import Config\n") do
      Mix.raise(~s[Could not find "use Mix.Config" or "import Config" in #{inspect(file)}])
    else
      [left, middle, right] ->
        write_formatted!(file, [left, middle, ?\n, to_inject, ?\n, right])
    end
  end

  def prod_only_config_inject(path, file, to_inject) do
    file = Path.join(path, file)

    contents =
      case File.read(file) do
        {:ok, bin} ->
          bin

        {:error, _} ->
          """
            import Config

            if config_env() == :prod do
            end
          """
      end

    case split_with_self(contents, "if config_env() == :prod do") do
      [left, middle, right] ->
        write_formatted!(file, [left, middle, ?\n, to_inject, ?\n, right])

      :error ->
        Mix.raise(~s[Could not find "if config_env() == :prod do" in #{inspect(file)}])
    end
  end

  defp write_formatted!(file, contents) do
    formatted = contents |> IO.iodata_to_binary() |> Code.format_string!()
    File.write!(file, [formatted, ?\n])
  end

  defp split_with_self(contents, text) do
    case :binary.split(contents, text) do
      [left, right] -> [left, text, right]
      [_] -> :error
    end
  end

  def put_binding(%Project{opts: opts} = project) do
    dev = Keyword.get(opts, :dev, false)
    commanded_path = commanded_path(project, dev)

    version = @commanded_version

    binding = [
      elixir_version: elixir_version(),
      app_name: project.app,
      app_module: inspect(project.app_mod),
      root_app_name: project.root_app,
      root_app_module: inspect(project.root_mod),
      commanded_application_module: inspect(Module.concat(project.app_mod, App)),
      commanded_router_module: inspect(Module.concat(project.app_mod, Router)),
      commanded_github_version_tag: "v#{version.major}.#{version.minor}",
      commanded_dep: commanded_dep(commanded_path, version),
      commanded_path: commanded_path,
      generators: nil_if_empty(project.generators),
      namespaced?: namespaced?(project),
      format_aliases: &format_aliases/1
    ]

    %Project{project | binding: binding}
  end

  defp format_aliases(aliases) do
    aliases
    |> Enum.group_by(& &1.namespace)
    |> Enum.map(fn {namespace, aliases} ->
      aliases = Enum.map(aliases, & &1.module) |> Enum.join(", ")

      "alias " <> namespace <> ".{" <> aliases <> "}"
    end)
    |> Enum.join("\n  ")
  end

  defp elixir_version do
    System.version()
  end

  defp namespaced?(project) do
    Macro.camelize(project.app) != inspect(project.app_mod)
  end

  defp nil_if_empty([]), do: nil
  defp nil_if_empty(other), do: other

  defp commanded_path(%Project{} = project, true) do
    absolute = Path.expand(project.project_path)
    relative = Path.relative_to(absolute, @commanded)

    if absolute == relative do
      Mix.raise("--dev projects must be generated inside Commanded directory")
    end

    project
    |> commanded_path_prefix()
    |> Path.join(relative)
    |> Path.split()
    |> Enum.map(fn _ -> ".." end)
    |> Path.join()
  end

  defp commanded_path(%Project{}, false), do: "deps/commanded"

  defp commanded_path_prefix(%Project{}), do: ".."

  defp commanded_dep("deps/commanded", %{pre: ["dev"]}),
    do: ~s[{:commanded, github: "commanded/commanded", override: true}]

  defp commanded_dep("deps/commanded", version),
    do: ~s[{:commanded, "~> #{version}"}]

  defp commanded_dep(path, _version),
    do: ~s[{:commanded, path: #{inspect(path)}, override: true}]
end

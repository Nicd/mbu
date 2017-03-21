defmodule FBU.TaskUtils do
  @moduledoc """
  Utilities for project build tasks.
  """

  require Logger

  @elixir System.find_executable("elixir")

  @default_task_timeout 60000

  defmodule ProgramSpec do
    @moduledoc """
    Program that is executed with arguments. Name is used for prefixing logs.
    """
    defstruct [
      name: "",
      port: nil,
      pending_output: ""
    ]
  end

  defmodule WatchSpec do
    @moduledoc """
    Watch specification, target to watch and callback to execute on events.
    Name is used for prefixing logs.

    Callback must have arity 2, gets filename/path and list of events as arguments.
    """
    defstruct [
      name: "",
      path: "",
      callback: nil,
      pid: nil,
      name_atom: nil
    ]
  end

  @doc """
  Get configuration value.
  """
  def conf(key) when is_atom(key) do
    Application.get_env(:code_stats, key)
  end

  @doc """
  Get absolute path to a program in $PATH.
  """
  def exec_path(program) do
    System.find_executable(program)
  end

  @doc """
  Run the given Mix task and wait for it to stop before returning.

  See run_tasks/2 for the argument description.
  """
  def run_task(task, args \\ []) do
    run_tasks([{task, args}])
  end

  @doc """
  Run the given tasks in parallel and wait for them all to stop
  before returning.

  Valid task types:

  * `{task_name, args}`, where `task_name` is a Mix task name or module,
  * `task_name`, where `task_name` is a Mix task name or module to call without
    arguments, or
  * `task_function` where `task_function` is a function to call without arguments.
  """
  def run_tasks(tasks) do
    tasks

    |> Enum.map(fn
      task_name when is_atom(task_name) or is_binary(task_name) ->
        {task_name, []}

      {task_name, args} when is_atom(task_name) or is_binary(task_name) ->
        {task_name, args}

      fun when is_function(fun) ->
        fun
    end)

    # Convert module references to string task names
    |> Enum.map(fn
      {task_module, args} when is_atom(task_module) ->
        {Mix.Task.task_name(task_module), args}

      {task_name, args} when is_binary(task_name) ->
        {task_name, args}

      fun when is_function(fun) ->
        fun
    end)

    |> Enum.map(fn
      {task, args} ->
        # Rerun is used here to enable tasks being run again in watches
        fn -> Mix.Task.rerun(task, args) end

      fun when is_function(fun) ->
        fun
    end)

    |> run_funs(@default_task_timeout)
  end

  @doc """
  Run the given functions in parallel and wait for them all to stop
  before returning.

  Functions can either be anonymous functions or tuples of
  {module, fun, args}.
  """
  def run_funs(funs, timeout \\ @default_task_timeout) when is_list(funs) do
    funs
    |> Enum.map(fn
      fun when is_function(fun) ->
        Task.async(fun)
      {module, fun, args} ->
        Task.async(module, fun, args)
    end)
    |> Enum.map(fn task ->
      Task.await(task, timeout)
    end)
  end

  @doc """
  Start an external program with apprunner.

  Apprunner handles killing the program if BEAM is abruptly shut down.
  Name is used as a prefix for logging output.

  Options that can be given:

  - name: Use as name for logging, otherwise name of binary is used.
  - cd:   Directory to change to before executing.

  Returns ProgramSpec for the started program.
  """
  def exec(executable, args, opts \\ []) do
    name = Keyword.get(
      opts,
      :name,
      (executable |> Path.rootname() |> Path.basename())
    )

    options = [
      :exit_status, # Send msg with status when command stops
      args: [Path.join(__DIR__, "apprunner.exs") | [executable | args]],
      line: 1024 # Send command output as lines of 1k length
    ]

    options = case Keyword.get(opts, :cd) do
      nil -> options
      cd -> Keyword.put(options, :cd, cd)
    end

    Logger.debug("[Spawned] Program #{name}")

    %ProgramSpec{
      name: name,
      pending_output: "",
      port: Port.open(
        {:spawn_executable, @elixir},
        options
      )
    }
  end

  @doc """
  Start watching a path. Name is used for prefixing logs.

  Path can point to a file or a directory in which case all subdirs will be watched.

  Returns a WatchSpec.
  """
  def watch(name, path, fun) do
    name_atom = String.to_atom(name)
    {:ok, pid} = :fs.start_link(name_atom, String.to_charlist(path))
    :fs.subscribe(name_atom)

    Logger.debug("[Spawned] Watch #{name}")

    %WatchSpec{
      name: name,
      path: path,
      callback: fun,
      pid: pid,
      name_atom: name_atom
    }
  end

  @doc """
  Listen to messages from specs and print them to the screen.

  If watch: true is given in the options, will listen for user's enter key and
  kill programs if enter is pressed.
  """
  def listen(specs, opts \\ [])

  # If there are no specs, stop running
  def listen([], _), do: :ok

  def listen(spec, opts) when not is_list(spec) do
    listen([spec], opts)
  end

  def listen(specs, opts) when is_list(specs) do
    # Start another task to ask for user input if we are in watch mode
    task = with \
      true        <- Keyword.get(opts, :watch, false),
      nil         <- Keyword.get(opts, :task),
      {:ok, task} <- Task.start_link(__MODULE__, :wait_for_input, [self()])
    do
      Logger.info("Programs/watches started, press ENTER to exit.")
      task
    end

    specs = receive do
      # User pressed enter
      :user_input_received ->
        Logger.info("ENTER received, killing tasks.")
        Enum.each(specs, &kill/1)
        []

      # Program sent output with end of line
      {port, {:data, {:eol, msg}}} ->
        program = Enum.find(specs, program_checker(port))
        msg = :unicode.characters_to_binary(msg, :unicode)

        prefix = "[#{program.name}] #{program.pending_output}"

        Logger.debug(prefix <> msg)

        specs
        |> Enum.reject(program_checker(port))
        |> Enum.concat([
          %{program | pending_output: ""}
        ])

      # Program sent output without end of line
      {port, {:data, {:noeol, msg}}} ->
        program = Enum.find(specs, program_checker(port))
        msg = :unicode.characters_to_binary(msg, :unicode)

        specs
        |> Enum.reject(program_checker(port))
        |> Enum.concat([
          %{program | pending_output: "#{program.pending_output}#{msg}"}
        ])

      # Port was closed normally after being told to close
      {port, :closed} ->
        handle_closed(specs, port)

      # Port closed because the program closed by itself
      {port, {:exit_status, 0}} ->
        handle_closed(specs, port)

      # Program closed with error status
      {port, {:exit_status, status}} ->
        program = Enum.find(specs, program_checker(port))
        Logger.error("Program #{program.name} returned status #{status}.")
        raise "Failed status #{status} from #{program.name}!"

      # Port crashed
      {:EXIT, port, _} ->
        handle_closed(specs, port)

      # FS watch sent file event
      {_, {:fs, :file_event}, {file, events}} ->
        handle_events(specs, file, events)
    end

    listen(specs, Keyword.put(opts, :task, task))
  end

  @doc """
  Kill a running program returned by exec().
  """
  def kill(%ProgramSpec{name: name, port: port}) do
    if name != nil do
      Logger.debug("[Killing] #{name}")
    end

    send(port, {self(), :close})
  end

  @doc """
  Kill a running watch.
  """
  def kill(%WatchSpec{name: name, pid: pid}) do
    Logger.debug("[Killing] #{name}")
    Process.exit(pid, :kill)
  end

  @doc """
  Print file size of given file in human readable form.

  If old file is given as second argument, print the old file's size
  and the diff also.
  """
  def print_size(new_file, old_file \\ nil) do
    new_size = get_size(new_file)

    {prefix, postfix} = if old_file != nil do
      old_size = get_size(old_file)

      {
        "#{human_size(old_size)} -> ",
        " Diff: #{human_size(old_size - new_size)}"
      }
    else
      {"", ""}
    end

    Logger.debug("#{Path.basename(new_file)}: #{prefix}#{human_size(new_size)}.#{postfix}")
  end

  def wait_for_input(target) do
    IO.gets("")
    send(target, :user_input_received)
  end

  defp get_size(file) do
    %File.Stat{size: size} = File.stat!(file)
    size
  end

  defp human_size(size) do
    size_units = ["B", "kiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"] # You never know

    human_size(size, size_units)
  end

  defp human_size(size, [unit | []]), do: size_with_unit(size, unit)

  defp human_size(size, [unit | rest]) do
    if size > 1024 do
      human_size(size / 1024, rest)
    else
      size_with_unit(size, unit)
    end
  end

  defp size_with_unit(size, unit) when is_float(size), do: "#{Float.round(size, 2)} #{unit}"

  defp size_with_unit(size, unit), do: "#{size} #{unit}"

  # Utility to find program in spec list based on port
  defp program_checker(port) do
    fn
      %ProgramSpec{port: program_port} ->
        program_port == port

      %WatchSpec{} ->
        false
    end
  end

  # Utility to find watch in spec list based on path
  defp watch_checker(path) do
    fn
      %ProgramSpec{} ->
        false

      %WatchSpec{path: watch_path} ->
        # If given path is relative to (under) the watch path or is the same
        # path completely, it's a match.
        path != watch_path and Path.relative_to(path, watch_path) != path
    end
  end

  defp handle_closed(specs, port) do
    case Enum.find(specs, program_checker(port)) do
      %ProgramSpec{} = program ->
        Logger.debug("[Stopped] #{program.name}")

        specs
        |> Enum.reject(program_checker(port))

      nil ->
        # Program was already removed
        specs
    end
  end

  defp handle_events(specs, file, events) do
    file = to_string(file)
    case Enum.find(specs, watch_checker(file)) do
      %WatchSpec{name: name, callback: callback} ->
        Logger.debug("[#{name}] Changed #{inspect(events)}: #{file}")

        callback.(file, events)

      nil ->
        # Watch was maybe removed for some reason
        Logger.debug("[Error] Watch sent event but path was not in specs list: #{inspect(events)} #{file}")
    end

    specs
  end
end

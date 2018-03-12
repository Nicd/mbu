defmodule MBU.TaskUtils do
  @moduledoc """
  Utilities for project build tasks.
  """

  require Logger

  @elixir System.find_executable("elixir")

  @default_task_timeout 60000
  @watch_combine_time 200

  @typep task_name :: String.t | module
  @typep task_list :: [task_name | fun | {task_name, list}]

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

    Callback must have arity 1, gets list of 2-tuples representing change events,
    each containing path to changed file and list of events that occurred.
    """
    defstruct [
      name: "",
      path: "",
      callback: nil,
      pid: nil,
      name_atom: nil,
      events: [],
      waiting_to_trigger: false
    ]
  end

  @typedoc """
  A watch specification or program specification that is used internally to keep
  track of running programs and watches.
  """
  @type buildspec :: %WatchSpec{} | %ProgramSpec{}

  @doc """
  Run the given Mix task and wait for it to stop before returning.

  See run_tasks/2 for the argument description.
  """
  @spec run_task(task_name, list) :: any
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

  Arguments should be keyword lists. If an argument `deps: false` is given to a task
  that is an `MBU.BuildTask`, its dependencies will not be executed.
  """
  @spec run_tasks(task_list) :: any
  def run_tasks(tasks) when is_list(tasks) do
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

  Can be given optional timeout, how long to wait for the execution of a task.
  By default it's 60 seconds.
  """
  @spec run_funs([fun | {module, fun, [...]}], integer) :: any
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
  @spec exec(String.t, list, list) :: %ProgramSpec{}
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

  Path must point to a directory. All subdirs will be watched automatically.

  The callback function is called whenever changes occur in the watched directory. It
  will receive a list of 2-tuples, each tuple describing one change. Each tuple has
  two elements: path to the changed file and a list of change events for that file
  (returned from `:fs`).

  Instead of a callback function, you can also give a module name of an `MBU.BuildTask`.
  In that case, the specified task will be called without arguments and with `deps: false`.

  Watch events are combined so that all events occurring in ~200 milliseconds are
  sent in the same call. This is to avoid running the watch callback many times
  when a bunch of files change.

  **NOTE:** Never add multiple watches to the same path, or you may end up with
  unexpected issues!

  Returns a WatchSpec.
  """
  @spec watch(String.t, String.t, ([{String.t, [atom]}] -> any) | module) :: %WatchSpec{}
  def watch(name, path, fun_or_mod)

  def watch(name, path, fun_or_mod) when is_atom(fun_or_mod) do
    watch(name, path, fn _ -> run_task(fun_or_mod, deps: false) end)
  end

  def watch(name, path, fun_or_mod) when is_function(fun_or_mod) do
    name_atom = String.to_atom(name)
    {:ok, pid} = FileSystem.start_link(name: name_atom, dirs: [String.to_charlist(path)])
    FileSystem.subscribe(name_atom)

    Logger.debug("[Spawned] Watch #{name}")

    %WatchSpec{
      name: name,
      path: path,
      callback: fun_or_mod,
      pid: pid,
      name_atom: name_atom
    }
  end

  @doc """
  Listen to messages from the given specs and print them to the screen.

  If watch: true is given in the options, will listen for user's enter key and
  kill programs/watches if enter is pressed.
  """
  @spec listen(buildspec | [buildspec], list) :: any
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
        Logger.error("[Error] Program #{program.name} returned status #{status}.")
        handle_closed(specs, port)

      # Port crashed
      {:EXIT, port, _} ->
        handle_closed(specs, port)

      # FS watch sent file event
      {:file_event, _, {file, events}} ->
        handle_events(specs, file, events)

      # A watch was triggered after the timeout
      {:trigger_watch, path} ->
        handle_watch_trigger(specs, path)
    end

    listen(specs, Keyword.put(opts, :task, task))
  end

  @doc """
  Kill a running program or watch.
  """
  @spec kill(buildspec) :: any
  def kill(spec)

  def kill(%ProgramSpec{name: name, port: port}) do
    if name != nil do
      Logger.debug("[Killing] #{name}")
    end

    send(port, {self(), :close})
  end

  def kill(%WatchSpec{name: name, pid: pid}) do
    Logger.debug("[Killing] #{name}")
    Process.exit(pid, :kill)
  end

  @doc """
  Print file size of given file in human readable form.

  If old file is given as second argument, print the old file's size
  and the diff also.
  """
  @spec print_size(String.t, String.t) :: any
  def print_size(new_file, old_file \\ "") do
    new_size = get_size(new_file)

    {prefix, postfix} = if old_file != "" do
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

  @doc """
  Wait for user's enter key and send a message `:user_input_received` to the given
  target process when enter was pressed.

  This is exposed due to internal code structure and is not really useful to call
  yourself.
  """
  @spec wait_for_input(pid) :: any
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
        path == watch_path or Path.relative_to(path, watch_path) != path
    end
  end

  defp handle_closed(specs, port) do
    case Enum.find(specs, program_checker(port)) do
      %ProgramSpec{} = program ->
        Logger.debug("[Stopped] #{program.name}")

        specs
        |> Enum.reject(program_checker(port))

      _ ->
        # Program was already removed or was a watch that shouldn't be killed
        specs
    end
  end

  defp handle_events(specs, file, events) do
    file = to_string(file)
    case Enum.find(specs, watch_checker(file)) do
      %WatchSpec{path: path, waiting_to_trigger: waiting} = spec ->
        # Add to spec's events and start waiting to trigger events if not already
        # waiting
        spec_events = [{file, events} | spec.events]

        if not waiting do
          Process.send_after(self(), {:trigger_watch, path}, @watch_combine_time)
        end

        specs = Enum.reject(specs, watch_checker(path))
        [%{spec | events: spec_events, waiting_to_trigger: true} | specs]

      nil ->
        # Watch was maybe removed for some reason
        Logger.error("[Error] Watch sent event but path was not in specs list: #{inspect(events)} #{file}")
        specs
    end
  end

  defp handle_watch_trigger(specs, path) do
    case Enum.find(specs, watch_checker(path)) do
      %WatchSpec{name: name, callback: callback, events: events} = spec ->
        Logger.debug("[#{name}] Changed: #{inspect(events)}")

        callback.(events)

        specs = Enum.reject(specs, watch_checker(path))
        [%{spec | events: [], waiting_to_trigger: false} | specs]

      nil ->
        Logger.error("[Error] Watch triggered but did not exist anymore: #{inspect(path)}")
        specs
    end
  end
end

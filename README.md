# MBU: Mix Build Utilities

**Hex.pm:** [hex.pm/packages/mbu](https://hex.pm/packages/mbu)

**Hexdocs:** [hexdocs.pm/mbu](https://hexdocs.pm/mbu)

_MBU_ is a collection of utility functions and scripts to turn Mix into a build tool
like Make. Sort of. With it, you can write tasks that build parts of your system,
be it front end or back end, without having to leave the safety of Elixir.

Shortly put, MBU allows you to write Mix tasks that depend on other tasks and contains
helper functions and macros to make writing them easier. See the basic usage section
for code examples.

## Basic Usage

A typical MBU task looks like this:

```elixir
defmodule Mix.Task.Build.Css do
  use MBU.BuildTask
  import MBU.TaskUtils

  @deps [
    "build.scss",
    "build.assets"
  ]

  task _args do
    exec("css-processor", ["--output", "dist/css"]) |> listen()
  end
end
```

There are a few parts to note here:

* With MBU, you don't call `use Mix.Task`, instead you call `use MBU.BuildTask` that will
  insert the `task` macro and internally call `use Mix.Task`.
* You can define dependencies to your task with the `@deps` list. They are executed in
  parallel before your task is run. If you need to run a task without running the
  dependencies, you can use `MBU.TaskUtils.run_task/2` and give it the `deps: false`
  option.
* The task is enclosed in the `task` macro that handles running the dependencies and
  logging debug output. This is compared to the `run/1` function of an ordinary Mix task.
* You can execute programs easily with the `MBU.TaskUtils.exec/2` function that is in the `MBU.TaskUtils`
  module. It starts the program and returns a program spec that can be given to `MBU.TaskUtils.listen/2`.
  The listen function listens to output from the program and prints it on the screen.

MBU also has watch support both for watches builtin to commands and custom watches:

```elixir
defmodule Mix.Task.Watch.Css do
  use MBU.BuildTask
  import MBU.TaskUtils

  @deps [
    "build.css"
  ]

  task _args do
    [
      # Builtin watch
      exec("css-processor", ["--output", "dist-css", "-w"]),

      # Custom watch
      watch("CopyAssets", "/path/to/assets", fn _events -> File.cp_r!("from", "to") end)
    ]
    |> listen(watch: true)
  end
end
```

As you can see, there are two types of watches here. The `css-processor` command has its
own watch, activated with a command line flag `-w`. The second watch is a custom watch,
useful for when CLI tools don't have watch support or when you want to run custom Elixir
code. The `MBU.TaskUtils.watch/3` function takes in the watch name (for logging), directory
to watch and a callback function that is called for change events.

Here, the listening function is given an argument `watch: true`. The arguments makes it
listen to the user's keyboard input and if the user presses the enter key, the watches and
programs are stopped. Otherwise you would have to kill the task to stop them.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mbu` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:mbu, "~> 1.0.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/mbu](https://hexdocs.pm/mbu).

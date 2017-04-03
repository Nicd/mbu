defmodule MBU.BuildTask do
  @moduledoc """
  BuildTask contains the macros that are used for making the tasks look nicer.
  """

  @doc """
  Sets up the necessary things for a build task.

  Each build task should have `use MBU.BuildTask` at its beginning. BuildTask automatically
  requires Logger so that doesn't need to be added into the task itself.
  """
  defmacro __using__(_opts) do
    quote do
      use Mix.Task
      require Logger

      import MBU.BuildTask

      # Dependencies of the task that will be automatically run before it
      @deps []
    end
  end

  @doc """
  Replacement for Mix.Task's run/1, used similarly. Code inside will be run when the task
  is called, with @deps being run first unless `deps: false` is given in the arguments.
  """
  defmacro task(args, do: block) do
    quote do
      def run(unquote(args) = mbu_buildtask_args) do
        task = Mix.Task.task_name(__MODULE__)
        Logger.info("[Started] #{task}")

        if Keyword.get(mbu_buildtask_args, :deps, true) and not Enum.empty?(@deps) do
          MBU.TaskUtils.run_tasks(@deps)
        end

        unquote(block)

        Logger.info("[Finished] #{task}")
      end
    end
  end
end

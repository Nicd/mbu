defmodule FBUTest do
  use ExUnit.Case

  # Dependency functions to call in tasks
  defmodule Depfuns do
    def foo(), do: send(Process.whereis(:deps_test_runner), :foo)
    def bar(), do: send(Process.whereis(:deps_test_runner), :bar)
    def foo_no(), do: send(Process.whereis(:no_deps_test_runner), :foo)
    def bar_no(), do: send(Process.whereis(:no_deps_test_runner), :bar)
  end

  test "that a module using the task macro has a run function that takes one argument" do
    defmodule Mix.Task.Foo1 do
      use FBU.BuildTask

      task args do
        assert args == [1]
      end
    end

    assert Mix.Task.Foo1.run([1]) == :ok
  end

  test "that the macro works when given _ to denote ignored args" do
    defmodule Mix.Task.Foo2 do
      use FBU.BuildTask

      task _ do
        :ok
      end
    end

    assert Mix.Task.Foo2.run([]) == :ok
  end

  test "that deps are run before the task" do
    defmodule Mix.Task.Foo3 do
      use FBU.BuildTask

      @deps [
        &Depfuns.foo/0,
        &Depfuns.bar/0
      ]

      task _ do
        :ok
      end
    end

    Process.register(self(), :deps_test_runner)

    Mix.Task.Foo3.run([])
    assert_receive :foo
    assert_receive :bar
  end

  test "that deps are not run if deps: false is given" do
    defmodule Mix.Task.Foo4 do
      use FBU.BuildTask

      @deps [
        &Depfuns.foo_no/0,
        &Depfuns.bar_no/0
      ]

      task _ do
        :ok
      end
    end

    Process.register(self(), :no_deps_test_runner)

    Mix.Task.Foo4.run([1, 2, 3, 4, 5, deps: false])
    refute_receive :foo
    refute_receive :bar
  end
end

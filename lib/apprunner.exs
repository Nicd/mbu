defmodule MBU.AppRunner do
  @moduledoc """
  AppRunner is a script for ensuring that external apps are terminated
  properly when executed from BEAM.

  If you start an application that does not listen to STDIN from BEAM
  and BEAM is terminated, the application's STDIN is closed but it may
  never close. AppRunner is meant to sit in between, monitoring the
  STDIN pipe and killing the application if STDIN closes. This ensures
  no zombie processes are left behind if the host BEAM dies.

  Output from the application will be sent back to the host BEAM. If the
  application dies for any reason, AppRunner is also closed.
  """

  def wait_for_eof() do
    case IO.getn("", 1024) do
      :eof -> nil
      _ -> wait_for_eof()
    end
  end

  def exec(program, args) do
    os_exec(program, args, :os.type())
  end

  def get_pid(port) do
    case Port.info(port) do
      nil ->
        nil

      info when is_list(info) ->
        case Keyword.get(info, :os_pid) do
          nil -> nil
          pid -> Integer.to_string(pid)
        end
    end
  end

  def kill(pid) do
    System.find_executable("kill") |> System.cmd([pid])
  end

  def wait_loop(port) do
    receive do
      {_, {:data, {:eol, msg}}} ->
        msg |> :unicode.characters_to_binary(:unicode) |> IO.puts()

      {_, {:data, {:noeol, msg}}} ->
        msg |> :unicode.characters_to_binary(:unicode) |> IO.write()

      {_, :eof_received} ->
        get_pid(port) |> kill()
        :erlang.halt(0)

      {_, :closed} ->
        :erlang.halt(0)

      {_, {:exit_status, status}} ->
        :erlang.halt(status)

      {:EXIT, _, _} ->
        :erlang.halt(1)
    end

    wait_loop(port)
  end

  # Execute program based on OS
  defp os_exec(program, args, {:win32, _}) do
    # On Windows we cannot spawn batch scripts so we actually run
    # cmd.exe /c c:/path/to/script.cmd args
    real_args = ["/c", program | args]

    Port.open(
      {:spawn_executable, System.find_executable("cmd")},
      [
        :exit_status,
        :stderr_to_stdout, # Redirect stderr to stdout to log properly

        # This is a Windows specific flag for :os.open_port that hides the
        # opened command window. It prevents the window from flashing on the
        # screen and also redirects stdout properly. Without this flag, stdout
        # is not passed back to BEAM and cannot be logged.
        :hide,
        
        args: real_args,
        line: 1024
      ]
    )
  end

  defp os_exec(program, args, _) do
    Port.open(
      {:spawn_executable, program},
      [
        :exit_status,
        :stderr_to_stdout, # Redirect stderr to stdout to log properly
        args: args,
        line: 1024
      ]
    )
  end
end

[program | args] = System.argv()
port = MBU.AppRunner.exec(program, args)

Task.async(fn ->
  MBU.AppRunner.wait_for_eof()
  :eof_received
end)

MBU.AppRunner.wait_loop(port)

path = Path.expand("../deps/hologram/lib/hologram/reflection.ex", __DIR__)

old = """
  def beam_defs(beam_path) do
    {:ok, %{definitions: definitions}} = BeamFile.debug_info(beam_path)
    definitions
  end
"""

new = """
  def beam_defs(beam_path) do
    case BeamFile.debug_info(beam_path) do
      {:ok, %{definitions: definitions}} -> definitions
      _other -> []
    end
  rescue
    _error -> []
  end
"""

source = File.read!(path)

cond do
  String.contains?(source, new) ->
    IO.puts("Hologram reflection patch already applied")

  String.contains?(source, old) ->
    File.write!(path, String.replace(source, old, new))
    IO.puts("Applied Hologram reflection patch")

  true ->
    IO.warn("Hologram reflection patch did not match #{path}")
end

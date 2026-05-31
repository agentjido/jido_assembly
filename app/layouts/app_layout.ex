defmodule Jido.Campfire.Layouts.App do
  use Hologram.Component

  alias Hologram.UI.Runtime

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Jido Campfire</title>
        <link rel="stylesheet" href="/assets/css/app.css" />
        <script defer src="/assets/js/app.js"></script>
        <Runtime />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end

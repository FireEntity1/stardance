module OgImage
  # Minimal mission OG image: uses the mission's banner attachment when
  # present, otherwise renders a placeholder with the mission name. Full
  # art direction is deferred — this exists so the `<meta og:image>` link in
  # missions/show resolves to a 1200×630 PNG instead of 404'ing on social
  # previews.

  class Missions < Base
    PREVIEWS = {
      "default" => -> { new(sample_mission) }
    }.freeze

    class << self
      def sample_mission
        OpenStruct.new(name: "Wario-Ware Clone", banner: nil)
      end
    end

    def initialize(mission)
      @mission = mission
      super()
    end

    def render
      if @mission.banner&.attached?
        download_attachment(@mission.banner) || render_placeholder
      else
        render_placeholder
      end
    end

    private

    def render_placeholder
      r, g, b = hex_to_rgb("#0d0a26")
      @image = Vips::Image.black(WIDTH, HEIGHT).new_from_image([ r, g, b ]).cast(:uchar)
      draw_text(
        truncate_text(@mission.name, 40),
        x: 0, y: 0, size: 96, color: "#ffffff", gravity: "Center"
      )
    end

    def download_attachment(attachment)
      data = attachment.download
      @image = Vips::Image.new_from_buffer(data, "")
      @image = resize_image(@image, WIDTH, HEIGHT, cover: true)
      @image
    rescue StandardError => e
      Rails.logger.warn("OgImage::Missions: Failed to use banner: #{e.message}")
      nil
    end
  end
end

module OgImage
  class IndexPage < Base
    LOGO_PATH = Rails.root.join("app", "assets", "images", "landing", "hero", "drawing.png").to_s

    def initialize(title: nil, subtitle: nil)
      super()
      @title = title
      @subtitle = subtitle
    end

    def render
      create_dark_canvas
      place_logo
      draw_title if @title.present?
      draw_subtitle if @subtitle.present?
    end

    private

    def create_dark_canvas
      create_patterned_canvas
    end

    def place_logo
      return unless File.exist?(LOGO_PATH)

      place_image(
        LOGO_PATH,
        x: 0, y: 80,
        width: 340, height: 340,
        gravity: "Center",
        cover: false
      )
    end

    def draw_title
      draw_text(
        @title,
        x: 0,
        y: 130,
        size: 128,
        color: "#4d3228",
        gravity: "Center"
      )
    end

    def draw_subtitle
      draw_text(
        @subtitle,
        x: 0,
        y: 220,
        size: 40,
        color: "#5c4033",
        gravity: "Center"
      )
    end
  end
end

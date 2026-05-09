module OgImage
  class MockAttachment
    def initialize(attached: true)
      @attached = attached
    end

    def attached?
      @attached
    end

    def download
      return nil unless @attached
      placeholder_image
    end

    private

    def placeholder_image
      require "open-uri"
      URI.open("https://cataas.com/cat?width=800&height=600").read
    rescue StandardError
      Vips::Image.black(800, 600).draw_rect([ 232, 213, 183 ], 0, 0, 800, 600, fill: true).pngsave_buffer
    end
  end

  class MockMemberships
    def initialize(owner_name:)
      @owner_name = owner_name
    end

    def find_by(role:)
      return nil unless role == :owner
      OpenStruct.new(user: OpenStruct.new(display_name: @owner_name))
    end
  end

  class Base
    WIDTH = 1200
    HEIGHT = 630

    attr_reader :image

    def initialize
      @image = nil
    end

    def render
      raise NotImplementedError, "Subclasses must implement #render"
    end

    def to_png
      render
      image.pngsave_buffer
    end

    protected

    def draw_rounded_rect(x:, y:, width:, height:, radius: 24, fill: "#ffffff", fill_opacity: 1.0, stroke: nil, stroke_width: 0)
      r, g, b = hex_to_rgb(fill)
      rect = rounded_rect_mask(width, height, radius)

      if fill_opacity < 1.0
        a = (fill_opacity * 255).round
        overlay = rect * [ r, g, b, a ]
      else
        overlay = rect * [ r, g, b ]
        overlay = overlay.bandjoin(rect * 255) if image.bands == 4
      end

      @image = image.composite(overlay, :over, x: [ x ], y: [ y ])
    end

    def create_patterned_canvas(
      frame_color: "#b0805f",
      card_color: "#7a4b40",
      inset: 26,
      card_radius: 42
    )
      fr, fg, fb = hex_to_rgb(frame_color)
      cr, cg, cb = hex_to_rgb(card_color)

      canvas = solid_rgba(WIDTH, HEIGHT, fr, fg, fb)

      cw = WIDTH - inset * 2
      ch = HEIGHT - inset * 2
      card_mask = rounded_rect_mask(cw, ch, card_radius)
      card = solid_rgba(cw, ch, cr, cg, cb)
      card = card.extract_band(0, n: 3).bandjoin(card_mask)
      canvas = canvas.composite(card, :over, x: [ inset ], y: [ inset ])

      pattern_path = Rails.root.join("app", "assets", "images", "mask", "pattern.png").to_s
      if File.exist?(pattern_path)
        pattern = Vips::Image.new_from_file(pattern_path)
        pattern = pattern.resize(WIDTH.to_f / pattern.width, vscale: HEIGHT.to_f / pattern.height)

        pat_rgb = pattern.extract_band(0, n: 3)
        pat_alpha = pattern.bands >= 4 ? pattern.extract_band(3) : Vips::Image.black(WIDTH, HEIGHT).new_from_image(255).cast(:uchar)

        canvas_rgb = canvas.extract_band(0, n: 3)
        canvas_alpha = canvas.extract_band(3)

        blended = (canvas_rgb * pat_rgb / 255.0).cast(:uchar)
        mix = pat_alpha / 255.0
        inv_mix = mix.linear(-1.0, 1.0)
        canvas_rgb = (blended * mix + canvas_rgb * inv_mix).cast(:uchar)
        canvas = canvas_rgb.bandjoin(canvas_alpha)
      end

      @image = canvas
    end

    def draw_text(text, x:, y:, size: 48, color: "#ffffff", gravity: "NorthWest")
      r, g, b = hex_to_rgb(color)
      text_img = Vips::Image.text(text.to_s, font: "#{font_name} #{size}", dpi: 72)
      w, h = text_img.width, text_img.height
      colored = solid_rgba(w, h, r, g, b).extract_band(0, n: 3)
      overlay = colored.bandjoin(text_img).copy(interpretation: :srgb)

      tx, ty = apply_gravity(gravity, x, y, w, h)
      @image = image.composite(overlay, :over, x: [ tx ], y: [ ty ])
    end

    def draw_multiline_text(text, x:, y:, size: 48, color: "#ffffff", line_height: 1, max_chars: 35, max_lines: 3)
      lines = wrap_text(text, max_chars).take(max_lines)
      spacing = (size * line_height).to_i

      lines.each_with_index do |line, index|
        draw_text(line, x: x, y: y + (index * spacing), size: size, color: color)
      end

      lines.size
    end

    def place_image(attachment_or_path, x:, y:, width:, height:, gravity: "NorthWest", rounded: false, radius: 20, cover: true)
      thumb = load_source_image(attachment_or_path, width, height, cover: cover)
      return unless thumb

      if thumb.bands == 3
        full_alpha = Vips::Image.black(thumb.width, thumb.height).new_from_image(255).cast(:uchar)
        thumb = thumb.bandjoin(full_alpha)
      end

      if rounded
        mask = rounded_rect_mask(thumb.width, thumb.height, radius)
        existing_alpha = thumb.extract_band(3)
        thumb = thumb.extract_band(0, n: 3).bandjoin((existing_alpha * mask / 255.0).cast(:uchar))
      end

      thumb = thumb.copy(interpretation: :srgb)
      tx, ty = apply_gravity(gravity, x, y, thumb.width, thumb.height)
      @image = image.composite(thumb, :over, x: [ tx ], y: [ ty ])
    rescue StandardError => e
      Rails.logger.warn("OgImage: Failed to place image: #{e.message}")
    end

    def font_name
      @font_name ||= begin
        source = Rails.root.join("app", "assets", "fonts", "Roboto.ttf").to_s
        Vips::Operation.call("fontname", [ source ]).split(",").first
      rescue StandardError
        "Roboto"
      end
    end

    private

    def solid_rgba(w, h, r, g, b, a = 255)
      Vips::Image.new_from_memory(
        ([ r, g, b, a ].pack("C4") * w * h),
        w, h, 4, :uchar
      ).copy(interpretation: :srgb)
    end

    def hex_to_rgb(hex)
      h = hex.to_s.delete("#")
      if h.length == 3
        [ h[0] * 2, h[1] * 2, h[2] * 2 ].map { |v| v.to_i(16) }
      else
        [ h[0, 2], h[2, 2], h[4, 2] ].map { |v| v.to_i(16) }
      end
    end

    def rounded_rect_mask(width, height, radius)
      r = [ radius, width / 2, height / 2 ].min
      quarter = Vips::Image.black(r, r).draw_circle([ 255 ], r, r, r, fill: true).cast(:uchar)
      tl = quarter.extract_area(0, 0, r, r)
      tr = tl.fliphor
      bl = tl.flipver
      br = tl.rot180

      top = tl.join(Vips::Image.black(width - 2 * r, r).new_from_image(255).cast(:uchar), :horizontal).join(tr, :horizontal)
      mid = Vips::Image.black(width, height - 2 * r).new_from_image(255).cast(:uchar)
      bot = bl.join(Vips::Image.black(width - 2 * r, r).new_from_image(255).cast(:uchar), :horizontal).join(br, :horizontal)

      top.join(mid, :vertical).join(bot, :vertical)
    end

    def load_source_image(source, width, height, cover: true)
      img = if source.respond_to?(:download)
        data = source.download
        return nil unless data
        Vips::Image.new_from_buffer(data, "")
      elsif source.is_a?(String) && source.start_with?("http")
        require "open-uri"
        Vips::Image.new_from_buffer(URI(source).open.read, "")
      else
        load_image_file(source)
      end

      resize_image(img, width, height, cover: cover)
    rescue StandardError => e
      Rails.logger.warn("OgImage: Failed to load image: #{e.message}")
      nil
    end

    def load_image_file(path)
      Vips::Image.new_from_file(path, access: :sequential)
    end

    def resize_image(img, width, height, cover: true)
      if cover
        hscale = width.to_f / img.width
        vscale = height.to_f / img.height
        scale = [ hscale, vscale ].max
        img = img.resize(scale, vscale: scale)
        left = (img.width - width) / 2
        top = (img.height - height) / 2
        img.extract_area(left, top, width, height)
      else
        hscale = width.to_f / img.width
        vscale = height.to_f / img.height
        scale = [ hscale, vscale ].min
        img.resize(scale, vscale: scale)
      end
    end

    def apply_gravity(gravity, x, y, obj_width, obj_height)
      case gravity
      when "NorthWest"
        [ x, y ]
      when "NorthEast"
        [ WIDTH - x - obj_width, y ]
      when "SouthWest"
        [ x, HEIGHT - y - obj_height ]
      when "SouthEast"
        [ WIDTH - x - obj_width, HEIGHT - y - obj_height ]
      when "Center"
        [ (WIDTH - obj_width) / 2 + x, (HEIGHT - obj_height) / 2 + y ]
      else
        [ x, y ]
      end
    end

    def wrap_text(text, max_chars)
      words = text.to_s.split
      lines = []
      current_line = ""

      words.each do |word|
        if current_line.empty?
          current_line = word
        elsif (current_line.length + word.length + 1) <= max_chars
          current_line += " #{word}"
        else
          lines << current_line
          current_line = word
        end
      end
      lines << current_line unless current_line.empty?
      lines
    end

    def truncate_text(text, length)
      text.to_s.length > length ? "#{text[0, length - 3]}..." : text.to_s
    end
  end
end

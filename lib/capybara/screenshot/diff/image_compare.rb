require 'chunky_png'

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within som comparison
      # range considering color values and difference area size.
      class ImageCompare
        include ChunkyPNG::Color

        attr_reader :annotated_new_file_name, :annotated_old_file_name, :new_file_name, :old_file_name

        def initialize(new_file_name, old_file_name = nil, dimensions: nil, color_distance_limit: nil,
            area_size_limit: nil, shift_distance_limit: nil)
          @new_file_name = new_file_name
          @color_distance_limit = color_distance_limit
          @area_size_limit = area_size_limit
          @shift_distance_limit = shift_distance_limit
          @dimensions = dimensions
          @old_file_name = old_file_name || "#{new_file_name}~"
          @annotated_old_file_name = "#{new_file_name.chomp('.png')}_0.png~"
          @annotated_new_file_name = "#{new_file_name.chomp('.png')}_1.png~"
          reset
        end

        # Resets the calculated data about the comparison with regard to the "new_image".
        # Data about the original image is kept.
        def reset
          @max_color_distance = @color_distance_limit ? 0 : nil
          @max_shift_distance = @shift_distance_limit ? 0 : nil
          @left = @top = @right = @bottom = nil
        end

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsish if the old file does not exist or the image dimensions do not match.
        def quick_equal?
          return nil unless old_file_exists?
          return true if new_file_size == old_file_size

          old_bytes, new_bytes = load_image_files(@old_file_name, @new_file_name)
          return true if old_bytes == new_bytes

          images = load_images(old_bytes, new_bytes)
          old_bytes = new_bytes = nil # rubocop: disable Lint/UselessAssignment
          crop_images(images, @dimensions) if @dimensions

          return false if sizes_changed?(*images)
          return true if images.first.pixels == images.last.pixels

          return false unless @color_distance_limit || @shift_distance_limit

          @left, @top, @right, @bottom = find_top(*images)

          return true if @top.nil?

          if @area_size_limit
            @left, @top, @right, @bottom = find_diff_rectangle(*images)
            return true if size <= @area_size_limit
          end

          false
        end

        # Compare the two images referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        # Return `nil` if the old file does not exist or if the image dimensions do not match.
        def different?
          return nil unless old_file_exists?

          old_file, new_file = load_image_files(@old_file_name, @new_file_name)

          return not_different if old_file == new_file

          images = load_images(old_file, new_file)

          crop_images(images, @dimensions) if @dimensions

          old_img = images.first
          new_img = images.last

          if sizes_changed?(old_img, new_img)
            save_images(@annotated_new_file_name, new_img, @annotated_old_file_name, old_img)
            @left = 0
            @top = 0
            @right = old_img.dimension.width - 1
            @bottom = old_img.dimension.height - 1
            return true
          end

          return not_different if old_img.pixels == new_img.pixels

          @left, @top, @right, @bottom = find_diff_rectangle(old_img, new_img)

          return not_different if @top.nil?
          return not_different if @area_size_limit && size <= @area_size_limit

          annotated_old_img, annotated_new_img = draw_rectangles(images, @bottom, @left, @right, @top)

          save_images(@annotated_new_file_name, annotated_new_img,
              @annotated_old_file_name, annotated_old_img)
          true
        end

        def old_file_exists?
          @old_file_name && File.exist?(@old_file_name)
        end

        def old_file_size
          @old_file_size ||= old_file_exists? && File.size(@old_file_name)
        end

        def new_file_size
          File.size(@new_file_name)
        end

        def dimensions
          [@left, @top, @right, @bottom]
        end

        def size
          (@right - @left + 1) * (@bottom - @top + 1)
        end

        def max_color_distance
          calculate_metrics unless @max_color_distance
          @max_color_distance
        end

        def max_shift_distance
          calculate_metrics unless @max_shift_distance || !@shift_distance_limit
          @max_shift_distance
        end

        private

        def calculate_metrics
          old_file, new_file = load_image_files(@old_file_name, @new_file_name)
          if old_file == new_file
            @max_color_distance = 0
            @max_shift_distance = 0
            return
          end

          old_image, new_image = load_images(old_file, new_file)
          calculate_max_color_distance(new_image, old_image)
          calculate_max_shift_limit(new_image, old_image)
        end

        def calculate_max_color_distance(new_image, old_image)
          pixel_pairs = old_image.pixels.zip(new_image.pixels)
          @max_color_distance = pixel_pairs.inject(0) do |max, (p1, p2)|
            next max unless p1 && p2

            d = ChunkyPNG::Color.euclidean_distance_rgba(p1, p2)
            [max, d].max
          end
        end

        def calculate_max_shift_limit(new_img, old_img)
          (0...new_img.width).each do |x|
            (0...new_img.height).each do |y|
              shift_distance =
                shift_distance_at(new_img, old_img, x, y, color_distance_limit: @color_distance_limit)
              if shift_distance && (@max_shift_distance.nil? || shift_distance > @max_shift_distance)
                @max_shift_distance = shift_distance
                return if @max_shift_distance == Float::INFINITY # rubocop: disable Lint/NonLocalExitFromIterator
              end
            end
          end
        end

        def not_different
          clean_tmp_files
          false
        end

        def save_images(new_file_name, new_img, org_file_name, org_img)
          org_img.save(org_file_name)
          new_img.save(new_file_name)
        end

        def clean_tmp_files
          FileUtils.cp @old_file_name, @new_file_name
          File.delete(@old_file_name) if File.exist?(@old_file_name)
          File.delete(@annotated_old_file_name) if File.exist?(@annotated_old_file_name)
          File.delete(@annotated_new_file_name) if File.exist?(@annotated_new_file_name)
        end

        def load_images(old_file, new_file)
          [ChunkyPNG::Image.from_blob(old_file), ChunkyPNG::Image.from_blob(new_file)]
        end

        def load_image_files(old_file_name, file_name)
          old_file = File.binread(old_file_name)
          new_file = File.binread(file_name)
          [old_file, new_file]
        end

        def sizes_changed?(org_image, new_image)
          return unless org_image.dimension != new_image.dimension

          change_msg = [org_image, new_image].map { |i| "#{i.width}x#{i.height}" }.join(' => ')
          puts "Image size has changed for #{@new_file_name}: #{change_msg}"
          true
        end

        def crop_images(images, dimensions)
          images.map! do |i|
            if i.dimension.to_a == dimensions || i.width < dimensions[0] || i.height < dimensions[1]
              i
            else
              i.crop(0, 0, *dimensions)
            end
          end
        end

        def draw_rectangles(images, bottom, left, right, top)
          images.map do |image|
            new_img = image.dup
            new_img.rect(left - 1, top - 1, right + 1, bottom + 1, ChunkyPNG::Color.rgb(255, 0, 0))
            new_img
          end
        end

        def find_diff_rectangle(org_img, new_img)
          left, top, right, bottom = find_left_right_and_top(org_img, new_img)
          bottom = find_bottom(org_img, new_img, left, right, bottom)
          [left, top, right, bottom]
        end

        def find_top(old_img, new_img)
          old_img.height.times do |y|
            old_img.width.times do |x|
              return [x, y, x, y] unless same_color?(old_img, new_img, x, y)
            end
          end
        end

        def find_left_right_and_top(old_img, new_img)
          top = @top
          bottom = @bottom
          left = @left || old_img.width - 1
          right = @right || 0
          old_img.height.times do |y|
            (0...left).find do |x|
              next if same_color?(old_img, new_img, x, y)

              top ||= y
              bottom = y
              left = x
              right = x if x > right
              x
            end
            (old_img.width - 1).step(right + 1, -1).find do |x|
              unless same_color?(old_img, new_img, x, y)
                bottom = y
                right = x
              end
            end
          end
          [left, top, right, bottom]
        end

        def find_bottom(old_img, new_img, left, right, bottom)
          if bottom
            (old_img.height - 1).step(bottom + 1, -1).find do |y|
              (left..right).find do |x|
                bottom = y unless same_color?(old_img, new_img, x, y)
              end
            end
          end
          bottom
        end

        def same_color?(old_img, new_img, x, y)
          color_distance =
            color_distance_at(new_img, old_img, x, y, shift_distance_limit: @shift_distance_limit)
          if !@max_color_distance || color_distance > @max_color_distance
            @max_color_distance = color_distance
          end
          color_matches = color_distance == 0 || (@color_distance_limit && @color_distance_limit > 0 &&
              color_distance <= @color_distance_limit)
          return color_matches if !@shift_distance_limit || @max_shift_distance == Float::INFINITY

          shift_distance = (color_matches && 0) ||
              shift_distance_at(new_img, old_img, x, y, color_distance_limit: @color_distance_limit)
          if shift_distance && (@max_shift_distance.nil? || shift_distance > @max_shift_distance)
            @max_shift_distance = shift_distance
          end
          color_matches
        end

        def color_distance_at(new_img, old_img, x, y, shift_distance_limit:)
          org_color = old_img[x, y]
          if shift_distance_limit
            start_x = [0, x - shift_distance_limit].max
            end_x = [x + shift_distance_limit, new_img.width - 1].min
            xs = (start_x..end_x).to_a
            start_y = [0, y - shift_distance_limit].max
            end_y = [y + shift_distance_limit, new_img.height - 1].min
            ys = (start_y..end_y).to_a
            new_pixels = xs.product(ys)
            distances = new_pixels.map do |dx, dy|
              new_color = new_img[dx, dy]
              ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_color)
            end
            distances.min
          else
            ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_img[x, y])
          end
        end

        def shift_distance_at(new_img, old_img, x, y, color_distance_limit:)
          org_color = old_img[x, y]
          shift_distance = 0
          loop do
            bounds_breached = 0
            top_row = y - shift_distance
            if top_row >= 0 # top
              ([0, x - shift_distance].max..[x + shift_distance, new_img.width - 1].min).each do |dx|
                if color_matches(new_img, org_color, dx, top_row, color_distance_limit)
                  return shift_distance
                end
              end
            else
              bounds_breached += 1
            end
            if shift_distance > 0
              if (x - shift_distance) >= 0 # left
                ([0, top_row + 1].max..[y + shift_distance, new_img.height - 2].min)
                  .each do |dy|
                  if color_matches(new_img, org_color, x - shift_distance, dy, color_distance_limit)
                    return shift_distance
                  end
                end
              else
                bounds_breached += 1
              end
              if (y + shift_distance) < new_img.height # bottom
                ([0, x - shift_distance].max..[x + shift_distance, new_img.width - 1].min).each do |dx|
                  if color_matches(new_img, org_color, dx, y + shift_distance, color_distance_limit)
                    return shift_distance
                  end
                end
              else
                bounds_breached += 1
              end
              if (x + shift_distance) < new_img.width # right
                ([0, top_row + 1].max..[y + shift_distance, new_img.height - 2].min)
                  .each do |dy|
                  if color_matches(new_img, org_color, x + shift_distance, dy, color_distance_limit)
                    return shift_distance
                  end
                end
              else
                bounds_breached += 1
              end
            end
            break if bounds_breached == 4

            shift_distance += 1
          end
          Float::INFINITY
        end

        def color_matches(new_img, org_color, dx, dy, color_distance_limit)
          new_color = new_img[dx, dy]
          return new_color == org_color unless color_distance_limit

          color_distance = ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_color)
          color_distance <= color_distance_limit
        end
      end
    end
  end
end

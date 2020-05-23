module WatermarkHelper
    require "matrix"

    # fragments in diabetes are 1 day
    def get_fragment(fragment)
        filter_date = Date.parse(fragment) rescue nil
        if filter_date.nil?
            return []
        end
        retVal = []
        Store.select(:id, :item).each do |el|
            i = JSON(el.item)
            if Date.parse(i["time"]) == filter_date
                retVal << el
            end
        end
        return retVal
    end

    # fragmentsize in diabetes in is 1 day
    def all_fragments(fragment)
        retVal = []
        Store.pluck(:item).each { |item| retVal << Date.parse(JSON(item)["time"]).to_s }
        return retVal.uniq

    end

    def get_fragment_key(fragment_id, account_id)
        @wm = Watermark.where(account_id: account_id, fragment: fragment_id)
        if @wm.count == 0
            @wm = Watermark.new(account_id: account_id, 
                      fragment: fragment_id,
                      key: rand(10e8))
            @wm.save
        else
            @wm = @wm.first
        end
        return @wm.key
    end

    def apply_watermark(data, key)
        retVal = []
        ev = error_vector(key, data)
        i = 0
        data.each do |el|
            new_item = JSON.parse(el.item)
            new_item["value"] += ev[i]
            retVal << {id: el.id, item: new_item}.stringify_keys
            i += 1
        end
        return retVal
    end

    def error_scale(error_vector, data)
        range = 0.4
        max = 0.2
        return (Vector.elements(error_vector)*range).collect { |i| i - (range-max) }.to_a
    end

    def error_vector(seed, data)
        error_length = data.length
        srand(seed.to_i)
        retVal = []
        error_length.times{ retVal << rand }
        return error_scale(retVal, data)
    end

    def valid_account?(account_id)
        Doorkeeper::Application.find(account_id).present? rescue false
    end

    # a fragment is identified in diabetes with a date
    def valid_fragment?(fragment)
        Date.parse(fragment).present? rescue false
    end

    def basic_distance(x, y)
        (x-y)**2
    end

    def distance(x, y)
        require 'enumerable/standard_deviation'
        
        subset = 0..([x.length, y.length].min - 1)
        dist = subset.map { |i| basic_distance(x[i], y[i]) }.mean
        similarity = subset.map { |i| 1 - ((x[i]-y[i]).abs/y[i]) }.mean

        return dist, similarity
    end

    def default_key_length
        100
    end

end
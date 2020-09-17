module DataAccessHelper
    include WatermarkHelper

    def getData(params)
        require 'securerandom'
        if ENV["WATERMARK"].to_s == ""
            case params.to_s
            when ->(n) { n.starts_with?("id=") }
                @store = Store.find(params[3..-1])
            when ->(n) { n.starts_with?("day=") }
                day_filter = params[4..-1]
                @store = Store.where("key LIKE '%" + day_filter + "%'")
            else
                @store = Store.all
            end

            # merge and filter data
            tmp = Hash.new
            @store.each do |el|
                item = JSON.parse(el.item)
                if tmp[item["time"]].nil?
                    tmp[item["time"]] = {ids: [el.id], values:[item["value"]]}
                else
                    if item["value"] > 5 && item["value"] < 13
                        tmp[item["time"]][:ids] << el.id
                        tmp[item["time"]][:values] << item["value"]
                    end
                end
            end unless @store.nil?

            # compile response
            retVal = []
            tmp.each do |el|
                retVal << {
                    id: el.last[:ids],
                    item: {
                        deviceId: "aggregate",
                        type: "cbg",
                        units: "mmol/L",
                        time: el.first,
                        id: SecureRandom.hex,
                        value: el.last[:values].inject{ |sum, el| sum + el }.to_f / el.last[:values].size
                    }
                }.stringify_keys
            end

        else
            retVal = [] # not yet supported
        end
        return retVal        
    end

    def get_provision(params, logstr)
        retVal_type = container_format
        timeStart = Time.now.utc
        retVal_data = getData(params)
        if retVal_data.nil?
            retVal_data = []
        end
        timeEnd = Time.now.utc
        content = []
        case retVal_type.to_s
        when "JSON"
            if retVal_data.count > 0
                if retVal_data.first["item"].is_a? String
                    retVal_data.each { |el| content << JSON(el["item"]) } rescue nil
                else
                    retVal_data.each { |el| content << el["item"] } rescue nil
                end
            end
            content_hash = Digest::SHA256.hexdigest(content.to_json)
        when "RDF"
            retVal_data.each { |el| content << el["item"].to_s }
            content_hash = Digest::SHA256.hexdigest(content.to_s)
        else
            content = ""
            retVal_data.each { |el| content += el["item"].to_s + "\n" } rescue ""
            content_hash = Digest::SHA256.hexdigest(content.to_s)
        end
        param_str = request.query_string.to_s

        retVal = {
            "content": content,
            "usage-policy": container_usage_policy.to_s,
            "provenance": getProvenance(content_hash, param_str, timeStart, timeEnd)
        }.stringify_keys

        createLog({
            "type": logstr,
            "scope": retVal_data.map{|h| h["id"]}.flatten.sort.to_json}, # "all (" + retVal_data.count.to_s + " records)"},
            Digest::SHA256.hexdigest(retVal.to_json))

        return retVal
    end
end
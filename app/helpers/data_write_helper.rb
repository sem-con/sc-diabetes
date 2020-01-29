module DataWriteHelper
    def writeData(content, input, provenance)
        # write data to container store
        new_items = []
        begin
            if content.class == String
                if content == ""
                    render plain: "",
                           status: 500
                    return
                end
                content = [content]
            end

            # write provenance
            prov = Provenance.new( 
                input_hash: Digest::SHA256.hexdigest(input.to_json),
                startTime: Time.now.utc)
            prov.save
            prov_id = prov.id

            # write data
            store_data = []
            Store.transaction do
                content.each do |item|
                    if !Store.find_by_key(item["time"])
                        my_store = Store.new(item: item.to_json, key: item["time"], prov_id: prov_id)
                        my_store.save
                        new_items << my_store.id
                        store_data << item
                    else
                        puts "DUPLICATE: " + item["time"].to_s
                    end
                end
            end

            if provenance.to_s == ""
                # retrieve information for provenance specific to PwD data
                first_measurement = content.first["time"].to_s
                last_measurement = content.last["time"].to_s
                deviceId = content.last["deviceId"]
                deviceType = content.last["type"]
                deviceUnit = content.last["units"]

                raw_data_hash = Digest::SHA256.hexdigest(content.to_json)
                store_data_hash = Digest::SHA256.hexdigest(store_data.to_json)
                device_hash = Digest::SHA256.hexdigest(deviceId.to_s)

                # Operator information
                init = RDF::Repository.new()
                init << RDF::Reader.for(:trig).new(Semantic.first.validation.to_s)
                uc = nil
                init.each_graph{ |g| g.graph_name == SEMCON_ONTOLOGY + "BaseConfiguration" ? uc = g : nil }
                container_title = RDF::Query.execute(uc) { pattern [:subject, RDF::URI.new(PURL_TITLE), :value] }.first.value.to_s rescue ""
                container_description = RDF::Query.execute(uc) { pattern [:subject, RDF::URI.new(PURL_DESCRIPTION), :value] }.first.value.to_s.strip rescue ""

                query = RDF::Query.new({
                    person: {
                        RDF.type  => RDF::Vocab::FOAF.Person,
                        RDF::Vocab::FOAF.name => :name,
                        RDF::Vocab::FOAF.mbox => :email,
                    }
                })
                operator_type = ""
                operator_name = query.execute(uc).first.name.to_s rescue ""
                operator_email = query.execute(uc).first.email.to_s.sub("mailto:","") rescue ""
                operator_hash = ""

                if operator_name == ""
                    query = RDF::Query.new({
                        person: {
                            RDF.type  => RDF::Vocab::FOAF.Organization,
                            RDF::Vocab::FOAF.name => :name,
                            RDF::Vocab::FOAF.mbox => :email,
                        }
                    })
                    operator_name = query.execute(uc).first.name.to_s rescue ""
                    operator_email = query.execute(uc).first.email.to_s.sub("mailto:","") rescue ""
                    if operator_name != ""
                        operator_type = "org"
                    end
                else
                    operator_type = "person"
                end
                if operator_name != "" && operator_email != ""
                   operator_hash = Digest::SHA256.hexdigest(
                        operator_name + " <" + operator_email + ">") # hash('name <email>')
                end


                # Entity: provided dataset
                prov_str = "scr:data_raw_" + store_data_hash[0,12] + "_" + device_hash[0,8] + " a prov:Entity;\n"
                prov_str += '    sc:dataHash "' + store_data_hash + '"^^xsd:string;' + "\n"
                prov_str += '    rdfs:label "collected raw data between ' + first_measurement + ' and ' + last_measurement + '"^^xsd:string;' + "\n"
                prov_str += '    prov:wasAttributedTo scr:diabetes_device_' + device_hash[0,12] + ';' + "\n"
                prov_str += '    prov:generatedAtTime "' + Time.now.utc.iso8601 + '"^^xsd:dateTime;' + "\n"
                prov_str += ".\n\n"

                # Agent: Diabetes Device
                prov_str += 'scr:diabetes_device_' + device_hash[0,12] + ' a prov:Agent;' + "\n"
                prov_str += '    sc:diabetesDeviceHash "' + device_hash + '"^^xsd:string;' + "\n"
                prov_str += '    sc:diabetesDeviceId "' + deviceId + '"^^xsd:string;' + "\n"
                prov_str += '    sc:diabetesDeviceType "' + deviceType + '" ;' + "\n"
                prov_str += '    rdfs:label "Diabetes device providing raw data"^^xsd:string;' + "\n"
                if operator_hash != ""
                    prov_str += '    prov:actedOnBehalfOf scr:operator_' + operator_hash[0,12] + ';' + "\n"
                end
                prov_str += ".\n\n"

                # Activity: collecting diabetes data
                prov_str += 'scr:collect_' + raw_data_hash[0,12] + ' a prov:Activity;' + "\n"
                prov_str += '    sc:collectHash "' + raw_data_hash + '"^^xsd:string;' + "\n"
                prov_str += '    rdfs:label "collection activity between ' + first_measurement + ' and ' + last_measurement + '"^^xsd:string;' + "\n"
                prov_str += '    prov:startedAtTime "' + first_measurement.to_datetime.utc.iso8601 + '"^^xsd:dateTime;' + "\n"
                prov_str += '    prov:endedAtTime "' + last_measurement.to_datetime.utc.iso8601 + '"^^xsd:dateTime;' + "\n"
                prov_str += '    prov:generated scr:data_raw_' + store_data_hash[0,12] + ';' + "\n"
                prov_str += ".\n\n"

                provenance = prov_str
            end

            Provenance.find(prov_id).update_attributes(
                prov: provenance,
                endTime: Time.now.utc)

            createLog({"type": "write", "scope": new_items.to_s})
            render plain: "",
                   status: 200

        rescue => ex
            puts "Error: " + ex.to_s
            render plain: "",
                   status: 500
        end
    end
end
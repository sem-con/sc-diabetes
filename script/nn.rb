require 'digest'
require 'date'

file = File.open("source.csv")
output = []
data = file.readlines.map(&:chomp)
data[2..data.length].each do |line|
	ts = line.split(",")[0].split(" ")
	day = ts[0]
	hour = ts[1]
	time = Date.strptime(ts[0], "%m/%d/%Y").strftime("%Y-%d-%m") + "T" + ts[1] + ":00"
	value = line.split(",")[1].to_i.to_s
	rec = '{"deviceId": "novo nordisk",'
	rec += '"type": "cgm",'
	rec += '"units": "mg/dL",'
	rec += '"time": "' + time + '",'
	rec += '"id":"' + Digest::MD5.hexdigest(time +  "_" + value) + '",'
	rec += '"value":' + value + "}"
	output << rec
end
File.write("output.json", "[" + output.join(",") + "]", mode: "w")

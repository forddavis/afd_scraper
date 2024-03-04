require 'nokogiri'
require 'pry-byebug'
require 'json'

# parse DCS_20240125/afd_25JAN2024.xml to json
DIRNAME = "DCS_20240125"
data = File.read("#{DIRNAME}/afd_25JAN2024.xml")
doc = Nokogiri::XML(data)

# Initialize an empty hash to store your data
airports_data = []

# Navigate to the `airport` element(s) you're interested in
doc.xpath('//airport').each do |airport|
  # Extract the aptid
  aptid = airport.at_xpath('aptid').text.strip

  airport_data = {}
  # Initialize the hash for this particular airport
  airport_data[:aptid] = aptid

  # Check for and extract navidname if it exists; it may not have text content
  navidname_element = airport.at_xpath('navidname')
  airport_data[:navidname] = navidname_element

  # Extract pages; initialize an empty array to hold the PDF references
  pages = []
  airport.xpath('pages/pdf').each do |pdf|
    pages << pdf.text.strip
  end

  # Only add the pages array if it's not empty
  airport_data[:pages] = pages unless pages.empty?

  # Add the airport hash to the airport_data array
  airports_data << airport_data
end

copy = airports_data.dup

copy.each_with_index do |airport, index|
  next unless airport.is_a?(Hash)
  next unless airport[:pages]
  aptid = airport[:aptid]

  ap_text = ""

  airport[:pages].each do |page|
    `pdftotext #{DIRNAME}/#{page} /tmp/#{page}.txt`
    ap_text += File.read("/tmp/#{page}.txt")
  end

  next if aptid == "1RL"
  ap_text = ap_text[ap_text.index("(SMK)(PAMK)")..-1] if aptid == "SMK"
  ap_text = ap_text[0..ap_text.index("(SMK)(PAMK)") - 1] if aptid == "KSM"
  ap_text = ap_text.split(/(–\s–)+/)
  ap_text = ap_text.map { |t| t.split("\n\n") }.flatten
  ap_text = ap_text.select { |a| a.include?("(#{aptid})") }

  if ap_text.size > 1
    ap_text = ap_text.select { |a| a[0..50].include?("(#{aptid})") }
  end


  ap_text = ap_text.first

  airports_data[index]["text"] = ap_text

  next unless ap_text

  regex = /(AWOS–3PT|AWOS–3P|AWOS|ASOS|ATIS DEP|ATIS ARR|ATIS).+?(\(?\d{3}\)?.?\d{3}.?\d{4})/

  airports_data[index]["freqs"] = ap_text.scan(regex).uniq
end

freqs = {}

airports_data.each do |port|
  aptid = port[:aptid]
  next if [nil, ""].include?(aptid)
  next if port["freqs"] == []

  freqs[aptid] = port["freqs"]
end

dups = airports_data.select{|a| a["freqs"] && a["freqs"].map(&:first).size != a["freqs"].map(&:first).uniq.size}

dups.each do |dup|
  new_freqs = []
  final_freqs = []
  dup["freqs"].each do |freq|
    new_freqs << freq + [freq.last.gsub(/\D/, "")]
  end

  added = []
  new_freqs.each do |freq|
    key = [freq.first, freq.last]
    next if added.include?(key)
    added << key
    final_freqs << freq.first(2)
  end

  freqs[dup[:aptid]] = final_freqs
end


File.write('freqs.json', freqs.to_json)

atis_a = []



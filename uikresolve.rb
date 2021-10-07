#!/usr/bin/env ruby

require 'set'
require 'json'
require 'net/http'
require 'nokogiri'

# не знаю, как это выглядит для других регионов
BASE_URL = URI('http://www.moscow-city.vybory.izbirkom.ru/region/moscow-city?action=ik')

# результаты работы прошлого этапа (mapfetch.rb)
map_data = File.open 'map.json' do |file|
  JSON.load file
end

# уникальные номера УИКов с карты нарушений
uik_ns = (map_data.map do |report| report['uik_n'] end).to_set.to_a

def fetch_uik_html(uik_n)
  req = Net::HTTP::Post.new(BASE_URL)
  # 403 для всех, кроме браузеров
  # но хватает подмены UA, чтобы обмануть
  req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9'
  # не я называла это поле
  req.set_form_data(:numik => uik_n.to_s)
  Net::HTTP.start(BASE_URL.hostname, BASE_URL.port) do |http|
    resp = http.request(req)
    # должен бы сам определять
    resp.body.encode('UTF-8', 'CP1251')
  end
end

def parse_member_tr(tr)
  cells = tr.css('td')
  # мы очень не хотим получить неправильное имя
  # тщательно проверяем формат
  raise "мне не нравится количество клеток" unless cells.length == 4
  raise "статус `" + cells[2] + "` вместо правильного" unless cells[2].content == "Председатель"
  {
    :name => cells[1].content,
    # вот эту информацию было бы интересно включить, но не смогла впихнуть в дизайн в итоге
    # сойдёт, у нас тут искусство, а не серьёзный анализ данных
    :source => cells[3].content,
  }
end

total_count = uik_ns.length
members = uik_ns.each_with_index.filter_map do |uik_n, counter|
  print "\rзапрашиваю УИК № " + uik_n.to_s + "; " + counter.to_s + "/" + total_count.to_s
  $stdout.flush

  html = fetch_uik_html uik_n
  doc = Nokogiri::HTML html
  # сложная часть
  # не то, чтобы тут было много с чем работать
  begin
    members = doc.css('div.table > table > tr:not(:nth(0))')[1..]
    first_member = members[0]
  rescue
    # некоторые УИКи просто не скачиваются
    # да, вручную тоже
    next if html.index('По данному запросу ничего не найдено') != nil
    raise
  end
  parsed_member = parse_member_tr(first_member)
  parsed_member[:uik_n] = uik_n
  parsed_member
end

puts "\rвсего найдено " + members.length.to_s + " председателей"
File.open('members.json', 'w') do |file|
  JSON.dump members, file
end
puts "результаты в members.json"

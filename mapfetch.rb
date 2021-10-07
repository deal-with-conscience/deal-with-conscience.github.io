#!/usr/bin/env ruby

# кстати, пока мы здесь
# почему мне вообще потребовалось это писать? не нашла кнопку для выгрузки на сайте

require 'json'
require 'net/http'
require 'nokogiri'

# выбрать в интерфейсе карты нарушений параметры поиска
# скопировать ссылку на результаты, вставить сюда
BASE_URL = 'https://www.kartanarusheniy.org/2021-09-19/s/850635141'

def fetch_page_html(page_n)
  Net::HTTP.get(URI(BASE_URL + '?page=' + page_n.to_s))
end

# пытаемся убеждаться, что парсим правильно
def assert_exactly_one(many)
  raise "должен быть только один элемент, а на самом деле " + many.to_s unless many.length == 1
  many[0]
end

def parse_id(possibly_id)
  raise "ожидался ID, на самом деле " + possibly_id.to_s unless possibly_id[..1] == 'ID'
  possibly_id[2..].to_i
end

def parse_tags_url(url)
  form = URI.decode_www_form(URI(url).query)
  raise "не распарсился URL" + form.to_s unless form.length == 1 and form[0].length == 2
  raise "неправильный ключ " + form[0][0] unless form[0][0] == "q[tags_id_in][]"
  form[0][1].to_i
end

# грязно парсим HTML, потому что иначе никак
def parse_reports(html)
  doc = Nokogiri::HTML(html)
  doc.css('.kn__b.kn__b--msg').filter_map do |raw_report|
    id = parse_id(assert_exactly_one(raw_report.css('.kn__msg-id > a.kn__msg-link')).content)
    uik_n_header = assert_exactly_one(raw_report.css('.kn__msg-tags div:nth(1)')).content
    uik_n = assert_exactly_one(raw_report.css('.kn__msg-tags div:nth(2)')).content
    tags = raw_report.css('ul > li.kn__msg-tags--name > a').map do |tag_link|
      parse_tags_url(tag_link.attr 'href')
    end
    { :id => id, :uik_n => uik_n.to_i, :tags => tags } if !!(uik_n.strip =~ /^[0-9]+$/) && uik_n_header.strip == 'УИК №'
  end
end

page_n = 1
reports = []
loop do
  print "\rскачиваю страницу " + page_n.to_s
  $stdout.flush

  new_reports = parse_reports(fetch_page_html page_n)
  break if new_reports.length == 0

  reports = reports.concat new_reports
  page_n += 1
end

# сверить глазами
puts "\rвсего найдено " + reports.length.to_s + " сообщений"
File.open('map.json', 'w') do |file|
  JSON.dump reports, file
end
puts "результаты в map.json"

#!/usr/bin/env ruby

require 'set'
require 'json'
require 'liquid'
require 'fileutils'

# нужен для ссылок на карту нарушений
REGION_ID = '11'
# а это менять не надо
UIK_BASE_URL = (
  'http://www.kartanarusheniy.org/2021-09-19/search?q%5Bregion_id_eq%5D=' \
  + REGION_ID \
  + '&q%5Buik_cont%5D='
)

def title(s)
  s.split(/([[:alpha:]]+)/).map { |s| s.capitalize }.join
end

members = File.open('members.json') do |file|
  JSON.load file
end

tags_map = File.open('tagsmap.json') do |file|
  JSON.load file
end

map_data = File.open('map.json') do |file|
  JSON.load file
end

tags_by_uik = {}
map_data.each do |deal|
  if tags_by_uik[deal['uik_n']] == nil then
    tags_by_uik[deal['uik_n']] = SortedSet.new
  end

  deal['tags'].each do |tag|
    tags_by_uik[deal['uik_n']] << tag
  end
end

people = members.map do |person|
  tag_ns = tags_by_uik[person['uik_n']]

  # почему-то часть имён НАПИСАНА КАПСОМ
  person['name'] = title person['name']
  # сайт карты нарушений глючный: поиск по номеру УИКа ищет не точное совпадение, а подстроку
  # но мы с этим ничего сделать не можем
  person['uik_link'] = UIK_BASE_URL + person['uik_n'].to_s
  person['tags'] = tag_ns.map do |tag_n|
    # намеренно пропускаем некоторые нарушения
    # например, непонятно, на ком лежит ответственность за «нарушения в вышестоящих комиссиях»
    # также нам незачем учитывать всякие технические данные вроде «подана жалоба»
    next if not tags_map['descriptions'][tag_n.to_s]

    if tags_map['others'].keys.include? tag_n.to_s then
      # используем альтернативные названия для тегов вроде «Иные нарушения в день голосования»,
      # если это единственный тег из группы
      # вручную сортировать группы не надо, ID и так по порядку
      if tags_map['others'][tag_n.to_s]['after'].all? { |n| not tag_ns.include? n } then
        tags_map['others'][tag_n.to_s]['alt']
      else
        tags_map['descriptions'][tag_n.to_s]
      end
    else
      tags_map['descriptions'][tag_n.to_s]
    end
  end.compact

  # если после фильтрации тегов нарушений не осталось — пропускаем
  person unless person['tags'].empty?
end.compact

# возможно, по номеру УИКа было бы нагляднее?
# по алфавиту эффектнее, впрочем
people.sort_by! { |person| person['name'] }

index = File.read('templates/index.liquid')
index_tpl = Liquid::Template.parse(index, :error_mode => :strict)

File.open('dist/index.html', 'w') do |file|
  file.write index_tpl.render('people' => people)
end

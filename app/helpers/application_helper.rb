module ApplicationHelper
  def nav_link(label, path, icon_svg)
    active = current_page?(path)
    link_to path, class: "flex items-center gap-4 px-3 py-2 rounded-md text-sm font-semibold transition-colors group #{active ? 'text-white bg-white/10' : 'text-zinc-400 hover:text-white'}" do
      concat content_tag(:span, icon_svg.html_safe, class: "w-6 h-6 shrink-0")
      concat content_tag(:span, label)
    end
  end

  def album_gradient(album)
    gradients = %w[
      from-violet-700 from-rose-700 from-amber-700
      from-teal-700   from-blue-700  from-pink-700
      from-indigo-700 from-green-700 from-orange-700
    ]
    gradients[album.id % gradients.length]
  end

  def rating_color(rating)
    case rating.to_i
    when 9..10 then "text-green-400"
    when 7..8  then "text-emerald-400"
    when 5..6  then "text-yellow-400"
    else            "text-red-400"
    end
  end

  def time_greeting
    hour = Time.current.hour
    case hour
    when 5..11  then "Good morning"
    when 12..17 then "Good afternoon"
    else             "Good evening"
    end
  end
end

# -*- coding: utf-8 -*-

################################################################################
# USAGE: ruby moviewalker.rb mv19797 mv59740 mv59022 ...
# mv19797 mv59740 mv59022 are moviewalker id
################################################################################

require 'pp'
require 'mechanize'
require 'date'
require 'chronic'

# <div id="scheduleHeader" class="mwb"><p class="movieTitle"><a> が映画タイトル
# <div class="movieList"> 内の <h3><a> が映画館名
# <div class="movieList"> 内に <table> がスケジュール
# <div class="movieList"> 内の (<div class="movieListBox">)<ul class="titleIcon"><li class="titleIcon2(or3)"> が版(字幕版/吹替版)

class MovieTimeTable
  attr_reader :table, :runtime	# Array of DateTime of start time. runtime(minute)
  def initialize(texttable, runtime = 0)

    @runtime = runtime
    @table = texttable

    @table.map!{|r|
      r.map!{|c|
        c.delete!("映画館問合")
        c[/[^\(]+/]
      }
    }

    @table.delete_at(1)

    @table = @table.transpose

    @table.delete_if{|day|
      day.include?(nil)
    }

    @table.each{|d|
      d[1] = d[1].split(" ")
    }

    year = Date.today.year
    @table.map!{|d|
      month, day = d[0].split("/").map{|i| i.to_i}
      d[1].map{|t|
        DateTime.parse(Chronic.parse("%d-%02d-%02d %s"%[year, month, day, t]).to_s)	# for "2016/02/14 26:25"
      }
    }
    @table.flatten!
  end
  
  def each_show
    rt = Rational(@runtime, 1440)
    @table.each{|start|
      yield(start, start+rt)
    }
  end
  
  def to_s
    rt = Rational(runtime, 1440)
    @table.map{|t|
      t.strftime("%Y/%m/%d %H:%M")+"-"+(t+rt).strftime("%Y/%m/%d %H:%M")
    }.join("\n") + "\n" + runtime.to_s
  end

end

class MovieShow
  attr_reader :title, :theater, :version, :schedule
  def initialize(title, theater, version, schedule)
    @title = title
    @theater = theater
    @version = version
    @schedule = schedule
  end
  
  def to_s
    [@title, @theater, @version, @schedule].join("\n")
  end
  
  def print_google_calendar
    @schedule.each_show{|start, finish|
      puts [@title+(@version==""?"":" ")+@version,
            start.strftime("%Y/%m/%d"),
            start.strftime("%H:%M"),
            finish.strftime("%Y/%m/%d"),
            finish.strftime("%H:%M"),
            "FALSE",
            "映画",
            @theater,
            "TRUE",
            "off"].join(",")
    }
  end
end

def print_google_calendar(shows)
  puts "Subject,Start Date,Start Time,End Date,End Time,All Day Event,Description,Location,Private,Reminder On/Off"
  shows.each{|show|
    show.print_google_calendar
  }
end

################################################################################
if ARGV.size==0
  puts <<EOS
USAGE: ruby moviewalker.rb mv19797 mv59740 mv59022 ...
mv19797 mv59740 mv59022 are moviewalker id
EOS
  exit
end

#mov_id = "mv19797"	# jingi naki
#mov_id = "mv59740"	# snow white
#mov_id = "mv59022"	# okami shojoto kuro oji
#mov_id = "mv59165"	# zootopia
#mov_id = "mv60042"	# deadpool

shows = []
ARGV.each{|mov_id|
  # 映画タイトル 上映時間
  movinfo_agent = Mechanize.new
  movinfo_agent.user_agent = 'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)'
  movinfo_agent.get("http://movie.walkerplus.com/#{mov_id}/")
  
  runtime = movinfo_agent.page.search('//span[@property="v:runtime"]').text.to_i
  title = movinfo_agent.page.search('//a[@property="v:name"]').text

  # 各県の劇場
  prefs = %w(P_tokyo_23 P_tokyo_cities P_kanagawa P_chiba P_saitama P_ibaraki P_tochigi P_gunma)
  prefs.each{|pref|
    
    agent = Mechanize.new
    agent.user_agent = 'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)'
    agent.get("http://movie.walkerplus.com/#{mov_id}/schedule/#{pref}/")
    
    # puts agent.page.body
    
    movieList = agent.page.search('//div[@class="movieList"]')
    movieList.each{|mov|
      th = mov.search('h3/a').text	# theater
      v = mov.search('ul[@class="titleIcon"]/li').text	# version
      texttable =  mov.search('th').each_slice(7).to_a.map{|i|
        i.map{|j|
          j.text
        }
      } << mov.search('td').map{|i|
        i.text
      }
      tt = MovieTimeTable.new(texttable, runtime)	# schedule
      shows << MovieShow.new(title, th, v, tt)
    }
  }
}
print_google_calendar(shows)

# shows.each{|show|
#   puts "@"*10
#   puts show
# }
__END__

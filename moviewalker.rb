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
        c.delete!("映画館問合休")
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

    year_crossing = false
    @table.map{|d|
      d[0] =~ /^\d+/
      $&.to_i
    }.inject{|mon_prev, mon|
      year_crossing ||= (mon_prev > mon)
      mon_prev = mon
    }

    cur_year = Date.today.year
    cur_mon = Date.today.month
    @table.map!{|d|
      month, day = d[0].split("/").map{|i| i.to_i}
      year = cur_year
      if year_crossing
        year += (cur_mon <=> month)
      end
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
  attr_reader :title, :theater, :remarks, :schedule
  def initialize(title, theater, remarks, schedule)
    @title = title
    @theater = theater
    @remarks = remarks
    @schedule = schedule
  end
  
  def to_s
    [@title, @theater, @remarks, @schedule].join("\n")
  end
  
  def google_calendar_string
    result = ""
    @schedule.each_show{|start, finish|
      result += [@title+(@remarks==""?"":" ")+@remarks,
                 start.strftime("%Y/%m/%d"),
                 start.strftime("%H:%M"),
                 finish.strftime("%Y/%m/%d"),
                 finish.strftime("%H:%M"),
                 "FALSE",
                 "映画",
                 @theater,
                 "TRUE",
                 "off"].join(",")
      result += "\n"
    }
    result
  end
end

def google_calendar_string(shows)
  result = [*" ".."~"].sample + "\n"
  result += "+Subject,Start Date,Start Time,End Date,End Time,All Day Event,Description,Location,Private,Reminder On/Off" + "\n"
  shows.each{|show|
    result += show.google_calendar_string
  }
  result
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
tmp_hash = Hash.new{|hash, key| hash[key]=true}
ARGV.each{|mv| tmp_hash[mv]}
mov_ids = tmp_hash.keys
mov_ids.each{|mov_id|
  # 映画タイトル 上映時間
  movinfo_agent = Mechanize.new
  movinfo_agent.user_agent = 'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)'
  movinfo_agent.get("http://movie.walkerplus.com/#{mov_id}/")
  
  runtime = movinfo_agent.page.search('//span[@property="v:runtime"]').text.to_i
  title = movinfo_agent.page.search('//a[@property="v:name"]').text

  # 各県の劇場
  prefs = %w(P_hyogo P_osaka P_kyoto)
  prefs.each{|pref|
    
    agent = Mechanize.new
    agent.user_agent = 'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)'
    agent.get("http://movie.walkerplus.com/#{mov_id}/schedule/#{pref}/")
    
    # puts agent.page.body
    
    movieList = agent.page.search('//div[@class="movieList"]')
    movieList.each{|mov|
      th = mov.search('h3/a').text	# theater
      rems = mov.search('ul[@class="titleIcon"]/li').map{|rem|
        rem.text
      }.delete_if{|rem|
        rem == "LAST" || rem =~ /上映終了日/
      }.join	# remarks
      texttable =  mov.search('th').each_slice(7).to_a.map{|i|
        i.map{|j|
          j.text
        }
      } << mov.search('td').map{|i|
        i.text
      }
      tt = MovieTimeTable.new(texttable, runtime)	# schedule
      shows << MovieShow.new(title, th, rems, tt)
    }
  }
}
open(DateTime.now.strftime("%Y%m%d%H%M%S")+".log", "wb"){|f|
  f.print google_calendar_string(shows)
}

# shows.each{|show|
#   puts "@"*10
#   puts show
# }
__END__

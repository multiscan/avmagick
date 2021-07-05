require 'erb'
require 'fileutils'
require 'imgkit'
require 'ostruct'
require 'time'
require 'yaml'

FF="/usr/local/bin/ffmpeg"
FFP="/usr/local/bin/ffprobe"
VCODEC="-c:v libx264 -pix_fmt yuv420p"
ACODEC="-c:a libfdk_aac -b:a 500k"
VFPS="25"
VSCALE="1280x720"

class Erber < OpenStruct
  def render(erb)
    erb.result(binding)
  end
end

def sec_to_time(t)
	s=t; 
	h=s/3600; s=s-3600*h
	m=s/60; s=s-60*m
	sprintf("%02d:%02d:%02d", h, m, s)
end

def log_and_system(c, f=nil)
	puts "---------------------------------------------------------------------"
	puts c
	puts "---------------------------------------------------------------------"
	unless f and File.exists?(f)
		system c
	end
end

def get_video_duration(f)
	# Get duration of the video
	ds=/Duration: ([0-9][0-9]:[0-9][0-9]:[0-9.]*),/.match(`#{FFP} #{f} 2>&1`)[1]
	Time.parse(ds)
end

# Example input.yml file:
# ---
# source_video: "SrcVideo"
# source_audio: "SrcAudio"
# split_audio: "Audio"
# workdir: "scratch"
# output: "Mixed"
# image_dir: "Images"
# title: 5                    # title duration (absent if == 0)
# template: "title.html.erb"  # (optional) template for automatic title images
# parts:
#   - 
#     v: 00001.MTS            # source video file name
#     a: 000327_0011.wav      # source audio file name
#     vc: 8                   # crop first vc seconds of video
#     vp: 0                   # prepend vp seconds to vide
#     d: a                    # output mixed file will be written in subdir d
#     ab: '00:00:44'          # audio begins at ab in source audio file
#     ae: '00:03:30'          # audio ends at ae in source audio file
#     title:                  # data for generating the title image from the template
#       image: aaa.png        # path to title image file in the title.dir directory 
#                               if given. Otherwise it will be generated from the
#                               template and the data provided (names are arbitrary)
#       composer: xxx
#       title: xxx
#       desc: xxx
#       artist: xxx


input=YAML.load(File.read("input.yml"));
SV_DIR=input['source_video'] || "SrcVideo"
SA_DIR=input['source_audio'] || "SrcAudio"
A_DIR=input['split_audio']   || "Audio"
W_DIR=input['workdir']       || "scratch"
M_DIR=input['output']        || "Mixed"
I_DIR=input['images_dir']    || "scratch"
input['ores'] ||= "1280x720"
input['ofps'] ||= "25"

title=input['title']
template = nil
template = ERB.new(File.read(input['template']).force_encoding("UTF-8")) if input['template']

parts=input['parts'].map{|p| OpenStruct.new(p)}

raise "Source video directory not found" unless Dir.exist?(SV_DIR)
raise "Source audio directory not found" unless Dir.exist?(SA_DIR)

# Create temporary work dirs
FileUtils.mkdir_p(A_DIR) unless Dir.exist?(A_DIR)
FileUtils.mkdir_p(W_DIR) unless Dir.exist?(W_DIR)
FileUtils.mkdir_p(I_DIR) unless Dir.exist?(I_DIR)

# Create all final output directories
parts.map{|p| p.d}.uniq.each do |d|
	md="#{M_DIR}/#{d}"
  	FileUtils.mkdir_p(md) unless File.directory?(md)
end

parts.each do |p|

	b=File.basename(p.v, ".MTS")
	vf="#{SV_DIR}/#{p.v}"
	raise "Source video file #{vf} not found" unless File.exist?(vf)

	ds=get_video_duration(vf)

	af="#{A_DIR}/#{b}.wav"
	c="#{FF} -i #{SA_DIR}/#{p.a}  -ss #{p.ab} -t #{p.ae} -async 1 -c:a copy #{af}"
	log_and_system(c, af)
	raise "Source audio file #{af} not found" unless File.exist?(af)

	afv="#{W_DIR}/#{b}_afv.wav"
	c="#{FF} -i #{SV_DIR}/#{p.v} -ss #{sec_to_time(p.vc)} -t 40 -vn -c:a pcm_s16le -ar 44100 -ac 1 #{afv}"
	log_and_system(c, afv)

	afa="#{W_DIR}/#{b}_afa.wav"
	c="#{FF} -i #{af} -t 40 -vn -c:a pcm_s16le -ar 44100 -ac 1 #{afa}"
	log_and_system(c, afa)

	dtf="#{W_DIR}/#{b}.dt"
	c="python align.py #{afa} #{afv} > #{dtf}"
	log_and_system(c, dtf)

	dt=File.read(dtf).chomp.to_f
	dts=sprintf("00:00:%07.4f", dt)
	# puts "#{b} -> #{dt}"

	ts="#{W_DIR}/#{b}_s.wav"
	c="#{FF}  -ss #{dts} -i #{afa} -i #{afv} -filter_complex '[0:a][1:a]join=inputs=2:channel_layout=stereo[a]' -map '[a]' #{ts}"
	log_and_system(c, ts)

	if title and p.title
		# If title image is not present, then create it from template
		p.title=OpenStruct.new(p.title)
		if p.title.image.nil? or p.title.image.empty?
			p.title.image = "#{I_DIR}/#{b}.png"
			unless File.exists?(p.title.image)
				html = Erber.new(p.title).render(template)
				kit = IMGKit.new(html, :quality => 100)
				kit.to_file(p.title.image)
			end
		end
		# Now superpose it to a frame from the video so we get something of the correct size
		fframe="#{W_DIR}/#{b}_frame.png"
		c="#{FF} -i #{vf} -vf \"scale='trunc(ih*dar):ih',setsar=1/1\" -vframes 1 -q:v 2 #{fframe}"
		log_and_system(c, fframe)

		tcomp="#{W_DIR}/#{b}_titlecomp.png"
		# c="convert #{fframe} #{p.title.image} -gravity center -composite -resize 1440x1080! #{tcomp}"
		c="convert #{fframe} #{p.title.image} -gravity center -composite #{tcomp}"
		log_and_system(c, tcomp)

		tv="#{W_DIR}/#{b}_titlecomp.mp4"
		c="#{FF} -loop 1 -i #{tcomp} -f lavfi -i anullsrc -s #{VSCALE} -t #{input['title']} #{VCODEC} -tune stillimage #{tv}"
		log_and_system(c, tv)
	end

	mf="#{M_DIR}/#{p.d}/#{b}.mp4"
	if p.vp > 0
		dtas=sprintf("-ss 00:00:%07.4f", dt+p.vp)
		dtvs=sprintf("-ss 00:00:%07.4f", p.vp)
		ds=(ds+p.vp).strftime("%H:%M:%S.%3N")

		if title
			c="#{FF} -i #{tv} #{dtvs} -i #{vf} #{dtas} -i #{af} -filter_complex \"[1:v]fps=#{VFPS},scale=#{VSCALE}[v1];[0:v][0:a][v1][2:a]concat=n=2:v=1:a=1[outv][outa]\" -map \"[outv]\" -map \"[outa]\" -t #{ds} #{ACODEC} #{VCODEC} #{mf}"
		else
			c="#{FF} #{dtvs} -i #{vf} #{dtas} -i #{af} -t #{ds} -map 1:0 -map 0:0 #{ACODEC} -vcodec copy #{mf}"
		end
	else
		if p.vc > 0
			dtas=sprintf("-ss 00:00:%07.4f", dt+p.vp)
			dtvs=sprintf("-ss 00:00:%07.4f", p.vc)
			ds=(ds-p.vc).strftime("%H:%M:%S.%3N")
		else
			dtas=sprintf("-ss 00:00:%07.4f", dt)
			dtvs=""
			ds=ds.strftime("%H:%M:%S.%3N")
		end
		if title
		  c="#{FF} -i #{tv} #{dtas} -i #{af} #{dtvs} -i #{vf} -filter_complex \"[2:v]fps=#{VFPS},scale=#{VSCALE}[v1];[0:v][0:a][v1][1:a]concat=n=2:v=1:a=1[outv][outa]\" -map \"[outv]\" -map \"[outa]\" -t #{ds} #{ACODEC} #{VCODEC} #{mf}"
		else
		  c="#{FF} #{dtas} -i #{af} #{dtvs} -i #{vf} -t #{ds} -map 1:0 -map 0:0 #{ACODEC} -vcodec copy #{mf}"
		end
	end
	log_and_system(c, mf)
end

if input['concat']
	cfp="concat.txt"
	File.open(cfp, "w+") do |cf|
		parts.each do |p|
			b=File.basename(p.v, ".MTS")
			mf="#{M_DIR}/#{p.d}/#{b}.mp4"
			cf.puts "file #{mf}"
		end
	end

	tt=Time.parse(Date.today().to_s)
	t0=tt.to_i
	File.open("youtube.txt", "w+") do |cf|
		parts.each do |p|
			b=File.basename(p.v, ".MTS")
			mf="#{M_DIR}/#{p.d}/#{b}.mp4"
			tts=tt.strftime('%H:%M:%S')
			yt = (title and p.title and p.title.short) ? p.title.short : b
			cf.puts "#{tts} - #{yt}"
			tt=tt + (get_video_duration(mf).to_i - t0)
		end
	end

	cvf="concat.mp4"
	c =	"ffmpeg -f concat -safe 0 -i #{cfp} -c copy #{cvf}"
	log_and_system(c, cvf)
end



# rm -f aaa.txt aaa.mp4
# for iv in 03 04 ; do
#   rm -f ${iv}_titlecomp.png scratch/${iv}_titlecomp.mp4 Mixed/${iv}.mp4
#   convert scratch/${iv}_frame.png scratch/${iv}.png -gravity center -composite scratch/${iv}_titlecomp.png
#   ffmpeg -r 25 -loop 1 -t 3 -i scratch/${iv}_titlecomp.png -f lavfi -i anullsrc=r=48000 -t 3 -c:a libfdk_aac -b:a 500k -c:v libx264 -pix_fmt yuv420p -tune stillimage -s 1280x720 scratch/${iv}_titlecomp.mp4
#   ffmpeg -i scratch/${iv}_titlecomp.mp4 \
#          -ss 00:00:06.0000 -i SrcVideo/${iv}.MTS \
#          -ss 00:00:01.2307 -i Audio/${iv}.wav \
#          -filter_complex "[1:v]fps=25,scale=1280x720[v1];[0:v][0:a][v1][2:a]concat=n=2:v=1:a=1[outv][outa]" \
#          -map "[outv]" -map "[outa]" \
#          -t 00:00:30.000 -c:a libfdk_aac -b:a 500k -c:v libx264 -pix_fmt yuv420p Mixed/${iv}.mp4
#   echo "file ./Mixed/${iv}.mp4" >> aaa.txt
# done
# ffmpeg -f concat -safe 0 -i aaa.txt -c copy aaa.mp4



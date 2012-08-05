#!/usr/bin/env ruby
#    Rubyripper - A secure ripper for Linux/BSD/OSX
#    Copyright (C) 2007 - 2012  Bouke Woudstra (boukewoudstra@gmail.com)
#
#    This file is part of Rubyripper. Rubyripper is free software: you can
#    redistribute it and/or modify it under the terms of the GNU General
#    Public License as published by the Free Software Foundation, either
#    version 3 of the License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# NOTE Currently Data tracks are totally ignored for the cuesheet.
#
# The Cuesheet class is there to provide a Cuesheet.
# A cuesheet contains all necessary info to exactly reproduce
# the structure of a disc. It is used by advanced burning programs.
# The assumption is made that all tracks are ripped, why else would
# you need a cuesheet?
class Cuesheet
  
  FRAMES_A_SECOND = 75
  FRAMES_A_MINUTE = 60 * FRAMES_A_SECOND
  HIDDEN_FIRST_TRACK = 0
  
  attr_reader :cuesheet
  
  def initialize(disc, cdrdao, fileScheme, fileAndDir=nil, prefs=nil, deps=nil)
    @disc = disc
    @cdrdao = cdrdao
    @fileScheme = fileScheme
    @fileAndDir = fileAndDir ? fileAndDir : FileAndDir.instance
    @prefs = prefs ? prefs : Preferences::Main.instance()
    @deps = deps ? deps : Dependency.instance()
    @md = @disc.metadata
    @cuesheet = Array.new
  end

  def save
    @prefs.codecs.each do |codec|
      printDiscData
      @prefs.image ? printTrackDataImage(codec) : printTrackData(codec)
      saveCuesheet(codec)
    end
  end

  # for testing purposes
  def test_printDiscData ; printDiscData() ; end
  def test_printTrackDataImage(codec) ; printTrackDataImage(codec) ; end
  def test_printTrackData(codec) ; printTrackData(codec) ; end 
   
private

  def getCueFileType(codec)
    codec == 'mp3' ? 'MP3' : 'WAVE' 
  end

  def time(sector) # minutes:seconds:leftover frames
    minutes = sector / FRAMES_A_MINUTE 
    seconds = (sector % FRAMES_A_MINUTE) / FRAMES_A_SECOND
    frames = sector % FRAMES_A_SECOND
    return "#{sprintf("%02d", minutes)}:#{sprintf("%02d", seconds)}:#{sprintf("%02d", frames)}"
  end

  def printDiscData
    @cuesheet << "REM GENRE #{@md.genre}"
    @cuesheet << "REM DATE #{@md.year}"
    @cuesheet << "REM DISCID #{@disc.freedbDiscid}"
    @cuesheet << "REM FREEDB_QUERY \"#{@disc.freedbString}\""
    @cuesheet << "REM COMMENT \"Rubyripper #{$rr_version}\""
    @cuesheet << "PERFORMER \"#{@md.artist}\""
    @cuesheet << "TITLE \"#{@md.album}\""
  end
  
  # The trackinfo for an image rip is relatively simple, since we don't have to account
  # for the prepend / append preference since it's not relevant for image rips.
  def printTrackDataImage(codec)
    writeFileLine(codec)
    (1..@disc.audiotracks).each do |track|
      track == 1 ? printDataImageFirstTrack(track) : printDataImageOtherTracks(track)
    end
  end
  
  # First track is handled differently because of a possible hidden track before track 1
  # This in fact leads to the special case of a track zero
  def printDataImageFirstTrack(track)
    printTrackLine(track)
    printPregapForHiddenTrack(track)
    printTrackMetadata(track)
    printIndexImageFirstTrack(track)
  end
  
  def printDataImageOtherTracks(track)
    printTrackLine(track)
    printTrackMetadata(track)
    printIndexImageOtherTracks(track) if track != 1
  end
  
   #writes the location of the file in the Cue
  def writeFileLine(codec, track=nil)
    @cuesheet << "FILE \"#{File.basename(@fileScheme.getFile(track, codec))}\" #{getCueFileType(codec)}"
  end
  
  def printTrackLine(track)
    @cuesheet << "  TRACK #{sprintf("%02d", track)} AUDIO"
  end
  
  # if the hidden audio is not ripped, only write a pregap tag
  def printPregapForHiddenTrack(track)
    if @prefs.ripHiddenAudio == false && @disc.getStartSector(track) > 0
      @cuesheet << "  PREGAP #{time(@disc.getStartSector(track))}"
    end
  end
  
  # write the info for a single track
  def printTrackMetadata(track)
    @cuesheet << "    TITLE \"#{@md.trackname(track)}\""
    @cuesheet << "    PERFORMER \"#{@md.various? ? @md.getVarArtist(track) : @md.artist}\""
  end
  
  # If there are sectors before track 1, print an index 00 for sector 0
  def printIndexImageFirstTrack(track)
    if @prefs.ripHiddenAudio == true && @disc.getStartSector(track) > 0
      @cuesheet << "    INDEX 00 #{time(0)}"
      @cuesheet << "    INDEX 01 #{time(@disc.getStartSector(track))}"
    else
      @cuesheet << "    INDEX 01 #{time(0)}"
    end
  end

  def printIndexImageOtherTracks(track)
    if @cdrdao.getPregapSectors(track) > 0
      @cuesheet << "    INDEX 00 #{time(@disc.getStartSector(track))}"
      @cuesheet << "    INDEX 01 #{time(@disc.getStartSector(track) + @cdrdao.getPregapSectors(track))}"
    else # no pregap
      @cuesheet << "    INDEX 01 #{time(@disc.getStartSector(track))}"
    end
  end
  
  def printTrackData(codec)
    puts "WARNING: Cuesheets for track ripping doesn't work yet !!"
  end
  
  def repair_printTrackData(codec)
    (1..@disc.audiotracks).each do |track|
      if @cdrdao.preEmph?(track) && (@prefs.preEmphasis == 'cue' || !@deps.installed?('sox'))
        @cuesheet << "FLAGS PRE"
        puts "Added PRE(emphasis) flag for track #{track}." if @settings['debug']
      end

      # do not put Track 00 AUDIO, but instead only mention the filename
      # when a hidden track exists first enter the trackinfo, then the file
      if track == 1 && @disc.getStartSector(HIDDEN_FIRST_TRACK)
        writeFileLine(HIDDEN_FIRST_TRACK, 'wav')
        trackinfo(track)
        writeFileLine(track)
        # if there's a hidden track, start the first track at 0
        @cuesheet << "    INDEX 01 #{time(0)}"
      # when no hidden track exists write the file and then the trackinfo
      elsif track == 1
        writeFileLine(track)
        trackinfo(track)
      elsif @prefs.preGaps == "prepend" || @cdrdao.getPregap(track) == 0
        writeFileLine(track)
        trackinfo(track)
      else
        trackinfo(track)
      end
      
      trackindex(track)
    end
  end

  def trackindex(track)
    if @settings['pregaps'] == "append" && @cdrdao.getPregap(track) > 0 && track != 1
      @cuesheet << "    INDEX 00 #{time(@disc.getLengthSector(track-1) - @cdrdao.getPregap(track))}"
      writeFileLine(track)
      @cuesheet << "    INDEX 01 #{time(0)}"
    else
      # There is a different handling for track 1 and the rest
      # If no hidden audio track or modus is prepending
      if track == 1 && @disc.getStartSector(1) > 0 && !@disc.getStartSector(0)
        @cuesheet << "    INDEX 00 #{time(0)}"
        @cuesheet << "    INDEX 01 #{time(@cdrdao.getPregap(track))}"
      elsif track == 1 && @disc.getStartSector(0)
        @cuesheet << "    INDEX 01 #{time(0)}"
      elsif @settings['pregaps'] == "prepend" && @cdrdao.getPregap(track) > 0
        @cuesheet << "    INDEX 00 #{time(0)}"
        @cuesheet << "    INDEX 01 #{time(@cdrdao.getPregap(track))}"
      elsif track == 0 # hidden track needs index 00
        @cuesheet << "    INDEX 00 #{time(0)}"
      else # no pregap or appended to previous which means it starts at 0
        @cuesheet << "    INDEX 01 #{time(0)}"
      end
    end
  end
  
  def saveCuesheet(codec)
    file = File.new(@fileScheme.getCueFile(codec), 'w')
    @cuesheet.each{|line| file.puts(line)}
    file.close()
  end
end
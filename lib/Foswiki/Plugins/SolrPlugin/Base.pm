# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2019 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::SolrPlugin::Base;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::SolrPlugin ();
use WebService::Solr ();
use Error qw( :try );
use Encode ();

our $STARTWW = qr/^|(?<=[\s\(])/m;
our $ENDWW = qr/$|(?=[\s,.;:!?)])/m;

BEGIN {
  if ($Foswiki::Plugins::VERSION < 2.3) {
    # Pre-unicode Foswiki
    $WebService::Solr::ENCODE = 1;
    $WebService::Solr::DECODE = 1;
  } else {
    # Unicode Foswiki
    $WebService::Solr::ENCODE = 1;
    $WebService::Solr::DECODE = 0;
  }
}


##############################################################################
sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = {
    session => $session,
    url => $Foswiki::cfg{SolrPlugin}{Url},    # || 'http://localhost:8983',
    timeout => $Foswiki::cfg{SolrPlugin}{Timeout},
    optimizeTimeout => $Foswiki::cfg{SolrPlugin}{OptimizeTimeout},
    @_
  };
  bless($this, $class);

  $this->{iconOfType} = {
    'fa-file-text-o' => qr/^topic$/i,
    'fa-code-o' => qr/\.?(js|css)$/i,
    'fa-comment-o' => qr/^comment$/i,
    'fa-file-image-o' => qr/\.?(art|bmp|cdr|cdt|cpt|djv|djvu|gif|ico|ief|jng|jpe|jpeg|jpg|pat|pbm|pcx|pgm|png|pnm|ppm|psd|ras|rgb|svg|svgz|tif|tiff|webp|wbmp|xbm|xpm|xwd)$/i,
    'fa-file-video-o' => qr/\.?(3gp|asf|asx|avi|axv|dif|dl|dv|fli|flv|gl|lsf|lsx|m4v|mng|mov|movie|mp4|mpe|mpeg|mpg|mpv|mxu|ogv|qt|wm|wmv|wmx|wvx|swf|webm)$/i,
    'fa-file-audio-o' => qr/\.?(aif|aifc|aiff|amr|amr|au|awb|awb|axa|flac|gsm|kar|m3u|m3u|m4a|mid|midi|mp2|mp3|mpega|mpga|oga|ogg|pls|ra|ra|ram|rm|sd2|sid|snd|spx|wav|wax|weba|wma)$/i,
    'fa-file-archive-o' => qr/\.?(zip|tar|tar|rar|gz)$/i,
    'fa-file-pdf-o' => qr/\.?pdf$/i,
    'fa-file-excel-o' => qr/\.?xlsx?$/i,
    'fa-file-word-o' => qr/\.?docx?$/i,
    'fa-file-powerpoint-o' => qr/\.?pptx?$/i,
  } unless defined $this->{iconOfType};

  $this->{defaultIcon} = 'fa-file-o' unless defined $this->{defaultIcon};

  $this->{timeout} = 180 unless defined $this->{timeout};
  $this->{optimizeTimeout} = 600 unless defined $this->{optimizeTimeout};

  return $this;
}

##############################################################################
sub connect {
  my ($this) = @_;

  my $maxConnectRetries = 1; # ... was 3 before;
  my $tries;

  for ($tries = 1; $tries <= $maxConnectRetries; $tries++) {
    eval {
      $this->{solr} = WebService::Solr->new($this->{url}, {
        agent => LWP::UserAgent->new(
          agent => "Foswiki-SolrPlugin/$Foswiki::Plugins::SolrPlugin::VERSION",
          timeout => $this->{timeout},
          keep_alive => 1
        ),
        autocommit => 0,
      });
    };

    if ($@) {
      $this->log("ERROR: can't contact solr server: $@");
      $this->{solr} = undef;
    }

    last if $this->{solr};
    sleep 2;
  }

  return $this->{solr};
}

##############################################################################
sub log {
  my ($this, $logString, $noNewLine) = @_;

  print STDERR "$logString" . ($noNewLine ? '' : "\n");

  #Foswiki::Func::writeDebug($logString);
}

##############################################################################
sub isDateField {
  my ($this, $name) = @_;

  return ($name =~ /^((.*_dt)|createdate|date|timestamp)$/) ? 1 : 0;
}

##############################################################################
sub isSkippedWeb {
  my ($this, $web) = @_;

  my $skipwebs = $this->skipWebs;
  $web =~ s/\//\./g;

  # check all parent webs
  for (my @webName = split(/\./, $web); @webName; pop @webName) {
    return 1 if $skipwebs->{ join('.', @webName) };
  }

  return 0;
}

##############################################################################
sub isSkippedTopic {
  my ($this, $web, $topic) = @_;

  my $skipTopics = $this->skipTopics;
  return 1 if $skipTopics->{"$web.$topic"} || $skipTopics->{$topic};

  return 0;
}

##############################################################################
sub isSkippedAttachment {
  my ($this, $web, $topic, $attachment) = @_;

  return 1 if $web && $this->isSkippedWeb($web);
  return 1 if $topic && $this->isSkippedTopic($web, $topic);

  my $skipattachments = $this->skipAttachments;

  return 1 if $skipattachments->{"$attachment"};
  return 1 if $topic && $skipattachments->{"$topic.$attachment"};
  return 1 if $web && $topic && $skipattachments->{"$web.$topic.$attachment"};

  return 0;
}

##############################################################################
# List of webs that shall not be indexed
sub skipWebs {
  my $this = shift;

  my $skipwebs = $this->{_skipwebs};

  unless (defined $skipwebs) {
    $skipwebs = {};

    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipWebs}
      || "Trash, TWiki, TestCases";

    foreach my $tmpweb (split(/\s*,\s*/, $to_skip)) {
      $skipwebs->{$tmpweb} = 1;
    }

    $this->{_skipwebs} = $skipwebs;
  }

  return $skipwebs;
}

##############################################################################
# List of attachments to be skipped.
sub skipAttachments {
  my $this = shift;

  my $skipattachments = $this->{_skipattachments};

  unless (defined $skipattachments) {
    $skipattachments = {};

    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipAttachments} || '';

    foreach my $tmpattachment (split(/\s*,\s*/, $to_skip)) {
      $skipattachments->{$tmpattachment} = 1;
    }

    $this->{_skipattachments} = $skipattachments;
  }

  return $skipattachments;
}

##############################################################################
# List of topics to be skipped.
sub skipTopics {
  my $this = shift;

  my $skiptopics = $this->{_skiptopics};

  unless (defined $skiptopics) {
    $skiptopics = {};
    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipTopics}
      || 'WebRss, WebSearch, WebStatistics, WebTopicList, WebLeftBar, WebPreferences, WebSearchAdvanced, WebIndex, WebAtom, WebChanges, WebCreateNewTopic, WebNotify';
    foreach my $t (split(/\s*,\s*/, $to_skip)) {
      $skiptopics->{$t} = 1;
    }
    $this->{_skiptopics} = $skiptopics;
  }

  return $skiptopics;
}

##############################################################################
sub inlineError {
  my ($this, $text) = @_;
  return "<span class='foswikiAlert'>$text</span>";
}

##############################################################################
sub entityDecode {
  my ($this, $text) = @_;

  return "" unless defined $text;
  $text =~ s/&#(\d\d\d);/chr($1)/ge;

  return $text;
}

##############################################################################
sub urlDecode {
  my ($this, $text) = @_;

  # SMELL: not utf8-safe
  $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;

  return $text;
}

###############################################################################
sub normalizeWebTopicName {
  my ($this, $web, $topic) = @_;

  # better defaults
  $web ||= $this->{session}->{webName};
  $topic ||= $this->{session}->{topicName};

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  $web =~ s/\//\./g;    # normalize web using dots all the way

  return ($web, $topic);
}

###############################################################################
# compatibility wrapper
sub takeOutBlocks {
  my $this = shift;

  return Foswiki::takeOutBlocks(@_) if defined &Foswiki::takeOutBlocks;
  return $this->{session}->renderer->takeOutBlocks(@_);
}

###############################################################################
# compatibility wrapper
sub putBackBlocks {
  my $this = shift;

  return Foswiki::putBackBlocks(@_) if defined &Foswiki::putBackBlocks;
  return $this->{session}->renderer->putBackBlocks(@_);
}

##############################################################################
sub mapToIconFileName {
  my ($this, $type) = @_;

  my $foundIcon;

  foreach my $icon (keys %{$this->{iconOfType}}) {
    my $pattern = $this->{iconOfType}{$icon};
    if ($type =~ $pattern) {
      $foundIcon = $icon;
      last;
    }
  }

  $foundIcon = $this->{defaultIcon} unless $foundIcon;

  #print STDERR "$type => $foundIcon\n";

  return $foundIcon;
}

##############################################################################
sub getTopicSummary {
  my ($this, $web, $topic, $meta, $text) = @_;

  my $summary = '';

  unless ($meta) {
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  }

  my $field = $meta->get('FIELD', 'Summary');
  $summary = $field->{value} if $field && $field->{value};

  unless ($summary) {
    $field = $meta->get('FIELD', 'Teaser');
    $summary = $field->{value} if $field && $field->{value};
  }

  unless ($summary) {
    $field = $meta->get('PREFERENCE', 'SUMMARY');
    $summary = $field->{value} if $field && $field->{value};
  }

# unless ($summary) {
#   $summary = $this->getSection($web, $topic, $text, "teaser");
# }
#
# unless ($summary) {
#   $summary = $this->getSection($web, $topic, $text, "summary");
# }

  return '' unless defined $summary;

  $summary = $this->plainify($summary, $web, $topic);
  $summary =~ s/\n/ /g;

  return $summary;
}

################################################################################
sub getSection {
  my ($this, $web, $topic, $text, $name, $type) = @_;

  return unless $name;

  my $key = $web.'::'.$topic;
  my $sections = $this->{_sections}{$key};
  unless (defined $sections) {
    $text = Foswiki::Func::readTopic($web, $topic) unless defined $text;

    my $ntext;
    ($ntext, $sections) = Foswiki::parseSections($text); # SMELL: parseSection should be part of Foswiki::Func

    foreach my $s (@$sections) {
      $s->{text} = substr($ntext, $s->{start}, $s->{end} - $s->{start});
    }


    $this->{_sections}{$key} = $sections;
  }
  return unless defined $sections;

  foreach my $s (@$sections) {
    next if $s->{name} ne $name;
    next if $type && $s->{type} ne $type;
    return $s->{text}
  }

  return;
}

################################################################################
# wrapper around Foswiki::Func::getScriptUrlPath
# that really, _really_, __really__ returns a relative path even when
# called from the command line
sub getScriptUrlPath {
  my $this = shift;

  my $url = Foswiki::Func::getScriptUrlPath(@_);

  $url =~ s/^$this->{session}{urlHost}//;

  return $url;
}

################################################################################
sub plainify {
  my ($this, $text, $web, $topic) = @_;

  return '' unless defined $text;

  my $wtn = Foswiki::Func::getPreferencesValue('WIKITOOLNAME') || '';

  # from Foswiki:Extensions/GluePlugin
  $text =~ s/^#~~(.*?)$//gm;    # #~~
  $text =~ s/%~~\s+([A-Z]+[{%])/%$1/gs;    # %~~
  $text =~ s/\s*[\n\r]+~~~\s+/ /gs;        # ~~~
  $text =~ s/\s*[\n\r]+\*~~\s+//gs;        # *~~

  # from Fosiki::Render
  $text =~ s/\r//g;                         # SMELL, what about OS10?
  $text =~ s/%META:[A-Z].*?}%//g;

  $text =~ s/%WEB%/$web/g;
  $text =~ s/%TOPIC%/$topic/g;
  $text =~ s/%WIKITOOLNAME%/$wtn/g;

  while ($text =~ s/((?:%|\$perce?nt)$Foswiki::regex{tagNameRegex}(?:\{.*?\})?(?:%|\$perce?nt))//gs) {
    # nop
  }
  $text =~ s/["']?\}%["']?|["']?%\{["']?//g; # some leftsobers

  # Format e-mail to add spam padding (HTML tags removed later)
  $text =~ s/$STARTWW((mailto\:)?[a-zA-Z0-9-_.+]+@[a-zA-Z0-9-_.]+\.[a-zA-Z0-9-_]+)$ENDWW//gm;
  $text =~ s/<!--.*?-->//gs;    # remove all HTML comments
  $text =~ s/<(?!nop)[^>]*>/ /g;    # remove all HTML tags except <nop>

  # SMELL: these should have been processed by entityDecode() before
  $text =~ s/&#\d+;/ /g;            # remove html entities
  $text =~ s/&[a-z]+;/ /g;          # remove entities

  # keep only link text of legacy [[prot://uri.tld/ link text]]
  $text =~ s/
          \[
              \[$Foswiki::regex{linkProtocolPattern}\:
                  ([^\s<>"\]]+[^\s*.,!?;:)<|\]])
                      \s+([^\[\]]*?)
              \]
          \]/$3/gx;

  # remove brackets from [[][]] links
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$1 $2/g;

  # remove "Web." prefix from "Web.TopicName" link
  $text =~ s/$STARTWW(($Foswiki::regex{webNameRegex})\.($Foswiki::regex{wikiWordRegex}|$Foswiki::regex{abbrevRegex}))/$3/g;
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;    # remove heading formatting and hbar
  $text =~ s/[\+\-]+/ /g;               # remove special chars
  $text =~ s/^\s+//gm;                  # remove leading whitespace
  $text =~ s/\s+$//gm;                  # remove trailing whitespace
  $text =~ s/!(\w+)/$1/gs;              # remove all nop exclamation marks before words

  # remove/escape special chars
  $text =~ s/%\{\s*\}%//g;
  $text =~ s/#+/ /g;
  $text =~ s/\$perce?nt/ /g;
  $text =~ s/\$dollar/ /g;
  $text =~ s/[ \t]+/ /gms;
  $text =~ s/^\s*$//gms;
  $text =~ s/[\r\n]+/\\n/gms;           # keep linefeeds before ...
  $text = $this->discardIllegalChars($text);    # discarding invisible control characters and unused code points and then ...
  $text =~ s/\\n/\n/g;                          # add them back in

  return $text;
}

################################################################################
sub discardIllegalChars {
  my ($this, $string) = @_;

  # remove illegal characters
  $string =~ s/\p{C}/ /g;

  return $string;
}

################################################################################
sub getRawResponse {
  my ($this, $response) = @_;

  my $result = $response->raw_response->content();

  # delete stack trace from error message
  # SMELL: shall we decode-encode the json instead of regex-ing it out?
  $result =~ s/"trace"\s*:\s*"java.*"\s*,\s*("code"\s*:\s*"?500"?)/$1/gs;

  return $result;
}

##############################################################################
sub fromUtf8 {
  my $this = shift;

  return Encode::decode_utf8($_[0]);
}

##############################################################################
sub toUtf8 {
  my $this = shift;

  return Encode::encode('utf-8', $_[0]);
}

##############################################################################
sub getMimeType {
  my ($this, $fileName) = @_;

  my $mimeType;
  my $suffix = $fileName;

  if ($fileName =~ /\.([^.]+)$/) {
    $suffix = $1;
  }

  unless (defined $this->{_types}) {
    my $mimeTypesFile = $Foswiki::cfg{SolrPlugin}{MimeTypesFileName} || $Foswiki::cfg{MimeTypesFileName};
    $this->{_types} = Foswiki::Func::readFile($mimeTypesFile);
    $this->{_types} //= "";
  }

  if ($this->{_types} =~ /^([^#]\S*).*?\s$suffix(?:\s|$)/im) {
    $mimeType = $1;
  }

  return unless defined $mimeType;

  my ($type, $subType) = $mimeType =~ /^(.*)\/(.*)$/;

  return wantarray ? ($type, $subType) : $mimeType;
}

##############################################################################
sub getMappedMimeType {
  my ($this, $fileName) = @_;

  $fileName =~ s/\.tar\.gz$/.tgz/; # SMELL: sometimes not part of mime.types file

  my ($type, $subType) = $this->getMimeType($fileName);
  return unless defined $type;

  # decompose 'application' group in a more meaningful way
  if ($type eq 'application') {

    # chart
    if ($subType =~ /chart|visio/) {
      $type = 'chart';
    }

    # presentation
    elsif ($subType  =~ /powerpoint|presentation|slide/) {
      $type = 'presentation';
    }

    # spreadsheet
    elsif ($subType =~ /numeric|spreadsheet|ms\-?excel/) {
      $type = 'spreadsheet';
    }

    # documents
    elsif ($subType =~ /document|ms\-?word|rtf/) {
      $type = 'document';
    }

    # pdf
    elsif ($subType =~ /pdf|postscript/) {
      $type = 'pdf';
    }

    # add to image
    elsif ($subType =~ /xcf/) {
      $type = 'image';
    }

    # add to video
    elsif ($subType =~ /swf|flash/) {
      $type = 'video';
    }

    # script
    elsif ($subType =~ /\b(js|json|sh|javascript)\b/) {
      $type = 'script';
    }

    # archive
    elsif ($subType =~ /\b(zip|tar|rar|compressed)\b/) {
      $type = 'archive';
    }

    # xml
    elsif ($subType =~ /xml\b/) {
      $type = 'xml';
    }

    # trash
    elsif ($subType =~ /x\-trash/) {
      $type = 'trash';
    }

    # binary
    elsif ($subType =~ /octet\-stream|x\-executable|x\-msdos\-program|x\-xpinstall/) {
      $type = 'binary';
    }

    # certificates
    elsif ($subType =~ /x\-x509|ca\-cert/) {
      $type = 'certificate';
    }

    # suppress any other application type
    else {
      return;
    }
  }

  # text based spreadsheets
  $type = 'spreadsheet' if $type eq 'text' && $subType eq 'csv';

  return wantarray ? ($type, $subType) : "$type/$subType";
}

1;

# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2025 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Contrib::Stringifier ();
use Error qw( :try );
use Encode ();
use File::Temp ();
use LWP::UserAgent ();
use HTTP::Request ();
use HTTP::Date ();
use MIME::Base64 ();
#use Data::Dump qw(dump);

our $STARTWW = qr/^|(?<=[\s\(])/m;
our $ENDWW = qr/$|(?=[\s,.;:!?)])/m;

use constant TRACE => 0;    # toggle me
use constant MAX_FILE_SIZE => 1014*1000*10;

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
    'fa-code-o' => qr/^(js|css)$/i,
    'fa-comment-o' => qr/^comment$/i,
    'fa-file-image-o' => qr/^(art|bmp|cdr|cdt|cpt|djv|djvu|gif|ico|ief|jng|jpe|jpeg|jpg|pat|pbm|pcx|pgm|png|pnm|ppm|psd|ras|rgb|svg|svgz|tif|tiff|webp|wbmp|xbm|xpm|xwd)$/i,
    'fa-file-video-o' => qr/^(3gp|asf|asx|avi|axv|dif|dl|dv|fli|flv|gl|lsf|lsx|m4v|mng|mov|movie|mp4|mpe|mpeg|mpg|mpv|mxu|ogv|qt|wm|wmv|wmx|wvx|swf|webm)$/i,
    'fa-file-audio-o' => qr/^(aif|aifc|aiff|amr|amr|au|awb|awb|axa|flac|gsm|kar|m3u|m3u|m4a|mid|midi|mp2|mp3|mpega|mpga|oga|ogg|pls|ra|ra|ram|rm|sd2|sid|snd|spx|wav|wax|weba|wma)$/i,
    'fa-file-archive-o' => qr/^(zip|tar|tar|rar|gz)$/i,
    'fa-file-pdf-o' => qr/^pdf$/i,
    'fa-file-excel-o' => qr/^xls[xm]?$/i,
    'fa-file-word-o' => qr/^doc[xm]?$/i,
    'fa-file-powerpoint-o' => qr/^ppt[xm]?$/i,
  } unless defined $this->{iconOfType};

  $this->{defaultIcon} = 'fa-file-o' unless defined $this->{defaultIcon};

  $this->{timeout} = 180 unless defined $this->{timeout};
  $this->{optimizeTimeout} = 600 unless defined $this->{optimizeTimeout};
  $this->{workArea} = Foswiki::Func::getWorkArea('SolrPlugin');

  return $this;
}

##############################################################################
sub finish {
  my $this = shift;

  undef $this->{_skipwebs};
  undef $this->{_skipattachments};
  undef $this->{_skiptopics};
  undef $this->{_sections};
  undef $this->{_types};
  undef $this->{_ua};
  undef $this->{solr};
}

##############################################################################
sub ua {
  my $this = shift;

  unless ($this->{_ua}) {
    $this->{_ua} = LWP::UserAgent->new(
      agent => "Foswiki-SolrPlugin/$Foswiki::Plugins::SolrPlugin::VERSION",
      timeout => $this->{timeout},
      keep_alive => 1
    );

    if ($Foswiki::cfg{PROXY}{HOST}) {
      my @noProxy = $Foswiki::cfg{PROXY}{NoProxy} ? split(/\s*,\s*/, $Foswiki::cfg{PROXY}{NoProxy}) : undef;
      $this->{_ua}->proxy(['http', 'https', 'ftp'], $Foswiki::cfg{PROXY}{HOST});
      $this->{_ua}->no_proxy(@noProxy) if @noProxy;
    }
  }

  return $this->{_ua};
}

##############################################################################
sub connect {
  my ($this) = @_;

  my $maxConnectRetries = 1; # ... was 3 before;
  my $tries;

  for ($tries = 1; $tries <= $maxConnectRetries; $tries++) {
    eval {
      $this->{solr} = WebService::Solr->new($this->{url}, {
        agent => $this->ua,
        autocommit => 0,
      });
    };

   if ($@) {
      $this->log("ERROR: can't contact solr server: $@");
      $this->{solr} = undef;
    };

    last if $this->{solr};
    sleep 2;
  }

  return $this->{solr};
}

##############################################################################
sub log {
  my ($this, $logString, $noNewLine) = @_;

  print STDERR "$logString\n";
  #print STDERR "\n" unless $noNewLine;

  #Foswiki::Func::writeDebug($logString);
}

##############################################################################
sub isDateField {
  my ($this, $name) = @_;

  return ($name =~ /^((.*_dt)|createdate|date)$/) ? 1 : 0;
}

##############################################################################
sub isImage {
  my ($this, $name) = @_;

  return ($name && $name =~ /\.(gif|jpe?g|png|bmp|svgz?|webp|tiff?|avif)$/i)?1:0;
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
    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipTopics} || 'TrashAttachments';
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
  my ($this, $typeOrFilename) = @_;

  my $type = $typeOrFilename;
  if ($typeOrFilename =~ /\.([^\.]+)$/) {
    $type = $1;
  }

  my $foundIcon;

  foreach my $icon (keys %{$this->{iconOfType}}) {
    my $pattern = $this->{iconOfType}{$icon};
    if ($type =~ $pattern) {
      $foundIcon = $icon;
      last;
    }
  }

  $foundIcon = $this->{defaultIcon} unless $foundIcon;

  $this->log("... mapping type '$type' to icon '$foundIcon'") if TRACE;

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

  return '' unless defined $text && $text ne "";
  $web ||= $this->{session}{webName};
  $topic ||= $this->{session}{topicName};

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

  # SMELL: ebook file extensions aren't found in mime.types most of the time
  if ($fileName =~ /\.(azw|azw3|azw4|cbz|cbr|cbc|chm|djvu|epub|fb2|fbz|htmlz|lit|lrf|mobi|prc|pdb|pml|rb|snb|tcr|txtz)$/) {
    return wantarray ? ("ebook", $1) : "application/$1"; # SMELL: mime type is just dummy here
  }

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
      $type = $subType || '';
      $type =~ s/^x\-//;
    }
  }

  # text based spreadsheets
  $type = 'spreadsheet' if $type eq 'text' && $subType eq 'csv';

  $this->log("fileName=$fileName, type=$type, subType=$subType") if TRACE;

  return wantarray ? ($type, $subType) : "$type/$subType";
}

################################################################################
sub deleteById {
  my ($this, $id) = @_;

  try {
    $this->{solr}->delete_by_id($id);
  } catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };
}

################################################################################
sub deleteByQuery {
  my ($this, $query) = @_;

  return unless $query;

  #$this->log("Deleting documents by query $query") if TRACE;

  my $success;
  try {
    $success = $this->{solr}->delete_by_query($query);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  return $success;
}

################################################################################
sub updateById {
  my ($this, $id, $key, $value, $oper) = @_;
  
  return; # SMELL: does not work
  return unless $this->{solr};

  $oper //= "set";

  my $doc = $this->newDocument();
  $doc->add_fields(id => $id);

  my $field = WebService::Solr::Field->new( $key => {
      $oper => $value
    }
  );
  $doc->add_fields($field);

  return $this->{solr}->add($doc);
}

################################################################################
sub newDocument {
  my $this = shift;

  return WebService::Solr::Document->new(@_);
}

################################################################################
# add a document to the index
sub add {
  my ($this, $doc) = @_;

  return unless $this->{solr};

  my $now = time();

  my $tsField = $this->getField($doc, "timestamp");
  if ($tsField) {
    $tsField->value($now);
  } else {
    $doc->add_fields(timestamp => $now) 
  }

  my $res = $this->{solr}->add($doc);

  my $webField = $this->getField($doc, "web");
  if ($webField) {
    my $web = $webField->value();
    my $id = "$web.WebHome";
    $this->updateById($id, "field_WebChangesDate_dt", $now);
  }

  return $res;
}

################################################################################
sub mirror {
  my ($this, $url, $mtime, $user, $password) = @_;

  my $ifModifiedSince = $mtime?HTTP::Date::time2str($mtime):0;
  $this->log("... downloading $url if modified since $ifModifiedSince") if TRACE;

  my $request = HTTP::Request->new("GET", $url);
  $request->header('If-Modified-Since' => $ifModifiedSince) if $mtime;

  if (defined $user && defined $password) {
    my $auth = MIME::Base64::encode_base64("$user:$password");
    $auth =~ s/\n$//;
    $request->header('Authorization' => "Basic $auth");
  }

  my $suffix = "";
  if ($url =~ /.*\.([^.]*)(?:\?.*)?$/) {
    $suffix = $1;
  }

  my $tmpFile = File::Temp->new(SUFFIX => ".$suffix");
  my $response = $this->ua->request($request, $tmpFile->filename);

  if ($response->header('X-Died')) {
    $this->log("ERROR: request died");
    return;
  }

  unless ($response->is_success) {
    $this->log("ERROR: request failed - ".$request->status_line);
    return;
  }

  return $tmpFile;
}

=begin TML

---++ solrRequest($path, $params)

low-level solr request

=cut

sub solrRequest {
  my ($this, $path, $params) = @_;

  my $response = $this->{solr}->generic_solr_request($path, $params);
  if ($response->is_error) {
    if (TRACE) {
      confess($response->error()."\n\nresponse:".$response->raw_response->content()."\n\n");
    } else {
      my $error = $response->error();
      $error =~ s/\sat\s.*//s;
      throw Error::Simple($error);
    }
  }

  return $response;
}

=begin TML

---++ ObjectMethod translate($string, $web, $topic) -> $string

translate string to user's current language

=cut

sub translate {
  my ($this, $string, $web, $topic) = @_;

  return $string if $string =~ /^<\w+ /; # don't translate html code

  my $result = $string;

  $string =~ s/^_+//;    # strip leading underscore as maketext doesnt like it

  my $context = Foswiki::Func::getContext();
  if ($context->{'MultiLingualPluginEnabled'}) {
    require Foswiki::Plugins::MultiLingualPlugin;
    $result = Foswiki::Plugins::MultiLingualPlugin::translate($string, $web, $topic);
  } else {
    $result = $this->{session}->i18n->maketext($string);
  }

  $result //= $string;

  return $result;
}

=begin TML

---++ ObjectMethod getSolrFieldNameOfFormfield($fieldDef, $default) -> $fieldName

translate a foswiki formfield name to a solr field name

=cut

sub getSolrFieldNameOfFormfield {
  my ($this, $fieldDef, $default) = @_;

  my $name;
  my $type;

  if (ref($fieldDef)) {
    $name = $fieldDef->{name};
    $type = $fieldDef->{type};
  } else {
    $name = $fieldDef;
    $type = "";
  }

  $type = $fieldDef->param("type") // 'autofill' if $type eq "autofill";

  my $fieldName = "";

  # date
  return 'field_' . $name . '_dt' if $type =~ /^date/;

  # floating numbers
  return 'field_' . $name . '_d' if $type =~ /^(number|percent|currency|rating)/;

  # integers 
  return 'field_' . $name . '_l' if $type =~ /^bytes/;

  # multi-valued types
  if ((ref($fieldDef) && $fieldDef->isMultiValued()) || $name =~ /TopicType/) {
    $fieldName = 'field_' . $name;
    $fieldName =~ s/(_(?:i|s|l|t|b|f|dt|lst))$//;

    $fieldName .= '_lst';
    return $fieldName;
  }

  if ($name =~ s/(_(?:i|s|l|t|b|f|dt|lst|d))$//) {
    return 'field_' . $name . $1;
  }

  $default //= "_s";

  return 'field_' . $name . $default;
}

################################################################################
sub getField {
  my ($this, $doc, $name) = @_;

  my @fields = ();
  foreach my $field ($doc->fields) {
    if ($field->name eq $name) {
      push @fields, $field;
    }
  }

  return wantarray ? @fields : $fields[0];
}

###############################################################################
sub getCacheTime {
  my ($this, $fileName) = @_;

  my $cacheTime = 0;
  my $obj = _cache()->get_object($fileName);
  $cacheTime = $obj->get_created_at() if $obj;

  return $cacheTime;
}

################################################################################
sub getStringifiedVersion {
  my ($this, $fileName, $mtime) = @_;

  return unless Foswiki::Contrib::Stringifier->canStringify($fileName);
  $mtime ||= 0;

  $this->log("... get stringified version of $fileName") if TRACE;

  my $request = Foswiki::Func::getRequestObject();
  my $doRefresh = Foswiki::Func::isTrue($request->param("refresh"));

  my $cacheTime = $doRefresh ? 0 : $this->getCacheTime($fileName);
  $mtime ||= _modificationTime($fileName) unless $fileName =~ /^(http|https|ftp):\/\//;

  my $attText;

  if ($mtime > $cacheTime) {
    $this->log("... caching stringified version of $fileName") if TRACE;

    my $tmpFile;
    if ($fileName =~ /^(http|https|ftp):\/\//) {
      $tmpFile = $this->mirror($fileName, $cacheTime);

      unless ($tmpFile) {
        $this->log("WARNING: error fetching $fileName");
        return;
      }

      $fileName = $tmpFile->filename();
    }

    unless (-e $fileName) {
      $this->log("WARNING: file not found - $fileName");
      return;
    }

    $attText = Foswiki::Contrib::Stringifier->stringFor($fileName) || '';

    # only cache the first 10MB at most, TODO: make size configurable
    if (length($attText) > MAX_FILE_SIZE) { 
      $this->log("WARNING: stripping down large file: $fileName");
      $attText = substr($attText, 0, MAX_FILE_SIZE);
    }

    _cache()->set($fileName, $attText);

  } else {
    $this->log("... found stringified version of $fileName in cache") if TRACE;
    $attText = _cache()->get($fileName) || '';
  }

  return $attText;
}

################################################################################
our %isMultiParam = (
  "fq" => 1,
  "facet.field" => 1,
  "facet.query" => 1
);

sub getRequestParams {
  my $this = shift;

  my $request = Foswiki::Func::getRequestObject();

  my %params = ();
  my @keys = $request->param();

  try {
    foreach my $key (@keys) {
      next if $key =~ /^(_|shards).*$/;
      my $val;
      if ($isMultiParam{$key}) {
        $val = [$request->multi_param($key)];
        foreach my $v (@$val) {
          throw Error::Simple("WARNING: detected potential log4j attack") if $v =~ /\bjndi:/;
        }
      } else {
        $val = $request->param($key);
        throw Error::Simple("WARNING: detected potential log4j attack") if $val =~ /\bjndi:/;
      }

      if ($key eq 'q' || $key eq 'search') {
        $val =~ s/[{}]//g;
      }

      if ($key eq 'qf') {
        $val = [split(/\s*,\s*/, $val)];
      }
      
      $params{$key} = $val;
    }
  } catch Error with {
    my $e = shift;
    $e =~ s/ at .*$//;
    $this->log($e);
    %params = ();
  };

  #print STDERR "request params=".dump(\%params)."\n";
  return \%params;
}

################################################################################
sub _modificationTime {
  my $filename = shift;

  my @stat = stat($filename);
  return $stat[9] || $stat[10] || 0;
}

################################################################################
sub _cache {
  # SMELL: hard-cded 7d cache expiry
  return Foswiki::Contrib::CacheContrib::getCache("SolrPlugin", "7 d");
}


1;

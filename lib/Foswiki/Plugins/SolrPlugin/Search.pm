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

package Foswiki::Plugins::SolrPlugin::Search;

=begin TML

---+ package Foswiki::Plugins::SolrPlugin::Search

This is the central service for all solr searches. Any search that you 
want to perform must go through this service. Most importantly this
service makes sure that Foswiki's access control lists are being evaluated
as part of every query. 

=cut

use strict;
use warnings;

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin ();
use POSIX ();
use Error qw(:try);
use JSON ();

use constant TRACE => 0; # toggle me

#use Data::Dump qw(dump);
#use Carp;

=begin TML

---++ ClassMethod new($session) -> $core

constructor for a Core object

=cut

sub new {
  my ($class, $session) = @_;

  my $this = $class->SUPER::new($session);

  $this->{url} = 
    $Foswiki::cfg{SolrPlugin}{SearchUrl} || $Foswiki::cfg{SolrPlugin}{Url};

  throw Error::Simple("no solr url defined") unless defined $this->{url};

  $this->log("ERROR: cannot connect solr daemon") unless $this->connect;

  return $this;
}

=begin TML

---++ handleSOLRSEARCH($params, $web, $topic) -> $result

handles the =%SOLRSEARCH= macro

=cut

sub handleSOLRSEARCH {
  my ($this, $params, $theWeb, $theTopic) = @_;

  #$this->log("called handleSOLRSEARCH(".$params->stringify.")") if TRACE;
  return $this->inlineError("can't connect to solr server") unless defined $this->{solr};

  my $theId = $params->{id};
  return '' if defined $theId && defined $this->{cache}{$theId};

  my $theQuery = $params->{_DEFAULT} // $params->{search} // '';;
  $theQuery = $this->entityDecode($theQuery);
  $params->{search} = $theQuery;

  my $theJump = Foswiki::Func::isTrue($params->{jump});

  if ($theJump && $theQuery) {
    # redirect to topic
    my ($web, $topic) = $this->normalizeWebTopicName($theWeb, $theQuery);

    if (Foswiki::Func::topicExists($web, $topic)) {
      my $url = Foswiki::Func::getScriptUrl($web, $topic, 'view');
      $this->{redirectUrl} = $url;
      return '';
    }
  }

  my $response = $this->doSearch($theQuery, $params);
  return '' unless defined $response;

  if (defined $theId) {
    $this->{cache}{$theId} = {
        response=>$response,
        params=>$params,
    };
  } 

  # I feel lucky: redirect to first result
  my $theLucky = Foswiki::Func::isTrue($params->{'lucky'});
  if ($theLucky) {
    my $url = $this->getFirstUrl($response);
    if ($url) {
      # will redirect in finishPlugin handler
      $this->{redirectUrl} = $url;
      return "";
    }
  }

  return $this->formatResponse($params, $theWeb, $theTopic, $response);
}

=begin TML

---++ handleSOLRFORMAT($params, $web, $topic) -> $result

handles the =%SOLRFORMAT= macro

=cut

sub handleSOLRFORMAT {
  my ($this, $params, $theWeb, $theTopic) = @_;

  #$this->log("called handleSOLRFORMAT(".$params->stringify.")") if TRACE;
  return '' unless defined $this->{solr};

  my $theId = $params->{_DEFAULT} || $params->{id};
  return $this->inlineError("unknown query id") unless defined $theId;

  my $cacheEntry = $this->{cache}{$theId};
  return $this->inlineError("unknown query '$theId'") unless defined $cacheEntry;

  $params = {%{$cacheEntry->{params}}, %$params};

  return $this->formatResponse($params, $theWeb, $theTopic, $cacheEntry->{response});
}

=begin TML

---++ formatResponse($params, $web, $topic, $response) -> $string

formats the search results fetched from the solr backend

=cut

sub formatResponse {
  my ($this, $params, $theWeb, $theTopic, $response) = @_;

  return '' unless $response;

  my $error;
  my $gotResponse = 0;
  try {
    $gotResponse = 1 if $response->content->{response} || $response->content->{grouped};
  } catch Error::Simple with {
    $this->log("Error parsing solr response") if TRACE;
    $error = $this->inlineError("Error parsing solr response");
  };
  return $error if $error;
  return '' unless $gotResponse;

  #$this->log("called formatResponse()") if TRACE;

  my $theFormat = $params->{format} // '';
  my $theHeader = $params->{header} // '';
  my $theFooter = $params->{footer} // '';
  my $theCorrection = $params->{correction} || 
    'Did you mean <a href=\'$url\' class=\'solrCorrection\'>%ENCODE{"$correction" type="quote"}%</a>';
  my $theFacets = $params->{facets};
  my $theHideSingle = $params->{hidesingle} // '';
  my $theCheckTopics = Foswiki::Func::isTrue($params->{checktopics}, 0);

  my %hideSingleFacets = map {$_ => 1} split(/\s*,\s*/, $theHideSingle);

  my $hilites;
  if ($theFormat =~ /\$hilite/ || $theHeader =~ /\$hilite/ || $theFooter =~ /\$hilite/) {
    $hilites = $this->getHighlights($response);
  }

  my $moreLikeThis;
  if ($theFormat =~ /\$morelikethis/ || $theHeader =~ /\$morelikethis/ || $theFooter =~ /\$morelikethis/) {
    $moreLikeThis = $this->getMoreLikeThis($response);
  }

  my $spellcheck = '';
  if ($theFormat =~ /\$spellcheck/ || $theHeader =~ /\$spellcheck/ || $theFooter =~ /\$spellcheck/) {
    my $correction = $this->getCorrection($response);
    if ($correction) {
      my $tmp = $params->{search};
      $params->{search} = $correction;
      my $scriptUrl = $this->getScriptUrl($theWeb, $theTopic, $params, $response);
      $spellcheck = $theCorrection;
      $spellcheck =~ s/\$correction/$correction/g;
      $spellcheck =~ s/\$url/$scriptUrl/g;
    }
  }

  my $page = $this->currentPage($response);
  my $limit = $this->entriesPerPage($response);
  my @rows = ();
  my $index = $page * $limit + 1;
  my $from = $index;
  my $to = $index + $limit - 1;
  my $totalEntries = $this->totalEntries($response);
  $to = $totalEntries if $to > $totalEntries;

  #$this->log("page=$page, limit=$limit, index=$index, count=$totalEntries") if TRACE;
  
  if (defined $theFormat && $theFormat ne '') {
    for my $doc ($response->docs) {
      my $line = $theFormat;
      my $id = '';
      my $type = '';
      my $topic;
      my $web;
      my $summary = '';

      my $theValueSep = $params->{valueseparator} || ', ';
      foreach my $name ($doc->field_names) {
        next unless $line =~ /\$$name/g;

        my @values = $doc->values_for($name);
        my $value = join($theValueSep, @values);

        $web = $value if $name eq 'web';
        $topic = $value if $name eq 'topic';
        $id = $value if $name eq 'id';
        $type = $value if $name eq 'type';
        $summary = $value if $name eq 'summary';

        $value = sprintf('%.02f', $value)
          if $name eq 'score';

        if ($this->isDateField($name)) {
          $line =~ s/\$$name\((.*?)\)/Foswiki::Time::formatTime(Foswiki::Time::parseTime($value), $1)/ge;
          $line =~ s/\$$name\b/Foswiki::Time::formatTime(Foswiki::Time::parseTime($value), '$day $mon $year')/ge;
        } else {
          $value = sprintf("%.02f kb", ($value / 1024))
            if $name eq 'size' && $value =~ /^\d+$/;
          $line =~ s/\$$name\b/$value/g;
        }

      }
      next if $theCheckTopics && !Foswiki::Func::topicExists($web, $topic);

      my $hilite = '';
      $hilite = ($hilites->{$id} || $summary) if $id && $hilites;

      my $mlt = '';
      $mlt = $moreLikeThis->{$id} if $id && $moreLikeThis;
      if ($mlt) {
        # TODO: this needs serious improvements
        #$line =~ s/\$morelikethis/$mlt->{id}/g;
      }

      my $itemFormat = 'attachment';
      $itemFormat = 'image' if $type =~ /^(gif|jpe?g|png|bmp|svg)$/i;
      $itemFormat = 'topic' if $type eq 'topic';
      $itemFormat = 'comment' if $type eq 'comment';
      $line =~ s/\$format/$itemFormat/g;
      $line =~ s/\$id/$id/g;
      $line =~ s/\$icon/$this->mapToIconFileName($type)/ge;
      $line =~ s/\$index/$index/g;
      $line =~ s/\$page/$page/g;
      $line =~ s/\$limit/$limit/g;
      $line =~ s/\$hilite/$hilite/g;
      $index++;
      push(@rows, $line);
    }
  }

  # format facets
  my $facetResult = '';
  my $facets = $this->getFacets($response);
  if ($facets) {

    foreach my $facetSpec (split(/\s*,\s*/, $theFacets)) {
      my ($facetLabel, $facetID) = parseFacetSpec($facetSpec);
      my $theFacetHeader = $params->{"header_$facetID"} // '';
      my $theFacetFormat = $params->{"format_$facetID"} // '';
      my $theFacetFooter = $params->{"footer_$facetID"} // '';
      my $theFacetSeparator = $params->{"separator_$facetID"} // '';
      my $theFacetExclude = $params->{"exclude_$facetID"};
      my $theFacetInclude = $params->{"include_$facetID"};

      next unless defined $theFacetFormat;

      my $shownFacetLabel = $facetLabel;
      $shownFacetLabel =~ s/_/ /g; #revert whitespace workaround

      my @facetRows = ();
      my $facetTotal = 0;

      # query facets
      if ($facetID eq 'facetquery') {
        my $theFacetQuery = $params->{facetquery} // '';
        my @facetQuery = split(/\s*,\s*/, $theFacetQuery);

        # count rows
        my $len = 0;
        foreach my $querySpec (@facetQuery) {
          my ($key, $query) = parseFacetSpec($querySpec);
          my $count = $facets->{facet_queries}{$key};
          next unless $count;
          next if $theFacetExclude && $key =~ /$theFacetExclude/;
          next if $theFacetInclude && $key !~ /$theFacetInclude/;
          $len++;
        }

        unless ($hideSingleFacets{$facetID} && $len <= 1) {
          foreach my $querySpec (@facetQuery) {
            my ($key, $query) = parseFacetSpec($querySpec);
            my $count = $facets->{facet_queries}{$key};
            next unless $count;
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetInclude/;
            $facetTotal += $count;
            my $line = $theFacetFormat;
            $key =~ s/_/ /g; #revert whitespace workaround
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$query\b/$query/g;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      }

      # date facets
      elsif ($this->isDateField($facetID)) {
        my $facet = $facets->{facet_ranges}{$facetLabel};
        next unless $facet;
        $facet = $facet->{counts};

        # count rows
        my $len = 0;
        for(my $i = 0; $i < scalar(@$facet); $i+=2) {
          my $key = $facet->[$i];
          my $count = $facet->[$i+1];
          next unless $count;
          next if $theFacetExclude && $key =~ /$theFacetExclude/;
          next if $theFacetInclude && $key !~ /$theFacetInclude/;
          $len++;
        }

        unless ($hideSingleFacets{$facetID} && $len <= 1) {
          for(my $i = 0; $i < scalar(@$facet); $i+=2) {
            my $key = $facet->[$i];
            my $count = $facet->[$i+1];
            next unless $count;
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetInclude/;
            $facetTotal += $count;
            my $line = $theFacetFormat;
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$date\((.*?)\)/Foswiki::Time::formatTime(Foswiki::Time::parseTime($key), $1)/ge;
            $line =~ s/\$date\b/Foswiki::Time::formatTime(Foswiki::Time::parseTime($key), '$day $mon $year')/ge;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      } 
      
      # field facet
      else {
        my $facet = $facets->{facet_fields}{$facetLabel};
        next unless defined $facet;

        # count rows
        my $len = 0;
        my $nrFacetValues = scalar(@$facet);
        for (my $i = 0; $i < $nrFacetValues; $i+=2) {
          my $key = $facet->[$i];
          next unless $key;
          next if $theFacetExclude && $key =~ /$theFacetExclude/;
          next if $theFacetInclude && $key !~ /$theFacetInclude/;
          $len++;
        }

        unless ($hideSingleFacets{$facetID} && $len <= 1) {
          for (my $i = 0; $i < $nrFacetValues; $i+=2) {
            my $key = $facet->[$i];
            next unless $key;

            my $count = $facet->[$i+1];

            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetInclude/;
            my $line = $theFacetFormat;
            $facetTotal += $count;
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      }
      my $nrRows = scalar(@facetRows);
      if ($nrRows > 0) {
        my $line = $theFacetHeader.join($theFacetSeparator, @facetRows).$theFacetFooter;
        $line =~ s/\$label\b/$shownFacetLabel/g;
        $line =~ s/\$id\b/$facetID/g;
        $line =~ s/\$total\b/$facetTotal/g;
        $line =~ s/\$rows\b/$nrRows/g;
        $facetResult .= $line;
      }
    }
  }

  # format interesting terms
  my $interestingResult = '';
  my $interestingTerms = $this->getInterestingTerms($response);
  if ($interestingTerms) {
    my $theInterestingExclude = $params->{exclude_interesting} // '';
    my $theInterestingInclude = $params->{include_interesting} // '';
    my $theInterestingHeader = $params->{header_interesting} // '';
    my $theInterestingFormat = $params->{format_interesting} // '';
    my $theInterestingSeparator = $params->{separator_interesting} // '';
    my $theInterestingFooter = $params->{footer_interesting} // '';

    my @interestingRows = ();
    while (my $termSpec = shift @$interestingTerms) {
      next unless $termSpec =~ /^(.*):(.*)$/g;
      my $field = $1; 
      my $term = $2; 
      my $score = shift @$interestingTerms;

      next if $theInterestingExclude && $term =~ /$theInterestingExclude/;
      next if $theInterestingInclude && $term =~ /$theInterestingInclude/;

      my $line = $theInterestingFormat;
      $line =~ s/\$term/$term/g;
      $line =~ s/\$score/$score/g;
      $line =~ s/\$field/$field/g;
      push(@interestingRows, $line);
    }
    if (@interestingRows) {
      $interestingResult = $theInterestingHeader.join($theInterestingSeparator, @interestingRows).$theInterestingFooter;
    }
  }

  my $groupResults = "";
  my $groups = $this->getGroups($response, $params->{group}); # SMELL: does not work with function or query grouping
  if ($groups) {
    my $theGroupHeader = $params->{header_group} // '';
    my $theGroupFooter = $params->{footer_group} // '';
    my $theGroupSeparator = $params->{separator_group} // '';
    my $theGroupFormat = $params->{format_group} // '';
    my $theGroupInclude = $params->{include_group};
    my $theGroupExclude = $params->{exclude_group};
    my $theValueSep = $params->{valueseparator} || ', ';

    my @groupRows = ();
    foreach my $group (@{$groups->{groups}}) {
      my $groupValue = $group->{groupValue};
      my $numFound = $group->{doclist}{numFound};
      next if defined $theGroupInclude && $groupValue !~ /$theGroupInclude/;
      next if defined $theGroupExclude && $groupValue =~ /$theGroupExclude/;

      my $index = 0;
      my @docRows = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        my $line = $theGroupFormat;
        while (my ($name, $value) = each %$doc) {
          next if $name =~ /^_/;

          next unless $line =~ /\$$name/g;

          $value = join($theValueSep, @$value) if ref($value);
          $value = sprintf('%.02f', $value) if $name eq 'score';

          if ($this->isDateField($name)) {
            $line =~ s/\$$name\((.*?)\)/Foswiki::Time::formatTime(Foswiki::Time::parseTime($value), $1)/ge;
            $line =~ s/\$$name\b/Foswiki::Time::formatTime(Foswiki::Time::parseTime($value), '$day $mon $year')/ge;
          } else {
            $value = sprintf("%.02f kb", ($value / 1024))
              if $name eq 'size' && $value =~ /^\d+$/;
            $line =~ s/\$$name\b/$value/g;
          }

          $line =~ s/\$index/$index/g;
          $line =~ s/\$groupValue/$groupValue/g;

          $index++;
        }
        push @docRows, $line if $line ne "";
      }

      my $docResult = $theGroupHeader.join($theGroupSeparator, @docRows).$theGroupFooter;
      $docResult =~ s/\$count/$numFound/g;
      $docResult =~ s/\$groupValue/$groupValue/g;

      push @groupRows, $docResult if $docResult ne "";
    }
    if (@groupRows) {
      $groupResults = join("", @groupRows);
    }
  }

  my $result;
  if (!@rows && $facetResult eq '' && $interestingResult eq '' && $groupResults eq '') {
    if (defined $params->{nullformat}) {
      $result = $params->{nullformat};
    } else {
      return "";
    }
  } else {
    $result = $theHeader.join($params->{separator} //'', @rows).$facetResult.$interestingResult.$groupResults.$theFooter;
  }

  $result =~ s/\$spellcheck/$spellcheck/g;
  $result =~ s/\$count/$totalEntries/g;
  $result =~ s/\$from/$from/g;
  $result =~ s/\$to/$to/g;
  $result =~ s/\$name//g; # cleanup
  $result =~ s/\$rows/0/g; # cleanup
  $result =~ s/\$morelikethis//g; # cleanup
  
  if ($params->{fields}) {
    my $cleanupPattern = '('.join('|', split(/\s*,\s*/, $params->{fields})).')';
    $cleanupPattern =~ s/\*/\\*/g;
    $result =~ s/\$$cleanupPattern//g;
  }

  if ($result =~ /\$pager/) {
    my $pager = $this->renderPager($theWeb, $theTopic, $params, $response);
    $result =~ s/\$pager/$pager/g;
  }

  if ($result =~ /\$seconds/) {
    my $seconds = sprintf("%0.3f", ($this->getQueryTime($response) / 1000));
    $result =~ s/\$seconds/$seconds/g;
  }

  # standard escapes
  $result =~ s/\$perce?nt/\%/g;
  $result =~ s/\$nop\b//g;
  $result =~ s/\$n/\n/g;
  $result =~ s/\$dollar/\$/g;

  #$this->log("result=$result");

  return $result;
}

=begin TML

---++ renderPager($web, $topic, $params. $response) -> $string

renders a result pager 

*Deprecated*: this function is rarely of use. any search result paging is done
via the Solr JavaScript interface instead

=cut

sub renderPager {
  my ($this, $web, $topic, $params, $response) = @_;

  return '' unless $response;

  my $lastPage = $this->lastPage($response);
  return '' unless $lastPage > 0;

  #print STDERR "lastPage=$lastPage\n";

  my $currentPage = $this->currentPage($response);
  my $result = '';
  if ($currentPage > 0) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $currentPage-1);
    $result .= "<a href='$scriptUrl' class='solrPagerPrev'>%MAKETEXT{\"Previous\"}%</a>";
  } else {
    $result .= "<span class='solrPagerPrev foswikiGrayText'>%MAKETEXT{\"Previous\"}%</span>";
  }

  my $startPage = $currentPage - 4;
  my $endPage = $currentPage + 4;
  if ($endPage >= $lastPage) {
    $startPage -= ($endPage-$lastPage+1);
    $endPage = $lastPage;
  }
  if ($startPage < 0) {
    $endPage -= $startPage;
    $startPage = 0;
  }
  $endPage = $lastPage if $endPage > $lastPage;

  if ($startPage > 0) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, 0);
    $result .= "<a href='$scriptUrl'>1</a>";
  }

  if ($startPage > 1) {
    $result .= "<span class='solrPagerEllipsis'>&hellip;</span>";
  }

  #$this->log("currentPage=$currentPage, lastPage=$lastPage, startPage=$startPage, endPage=$endPage") if TRACE;

  my $count = 1;
  my $marker = '';
  for (my $i = $startPage; $i <= $endPage; $i++) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $i);
    $marker = $i == $currentPage?'current':'';
    $result .= "<a href='$scriptUrl' class='$marker'>".($i+1)."</a>";
    $count++;
  }

  if ($endPage < $lastPage-1) {
    $result .= "<span class='solrPagerEllipsis'>&hellip;</span>"
  }

  if ($endPage < $lastPage) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $lastPage);
    $marker = $currentPage == $lastPage?'current':'';
    $result .= "<a href='$scriptUrl' class='$marker'>".($lastPage+1)."</a>";
  }

  if ($currentPage < $lastPage) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $currentPage+1);
    $result .= "<a href='$scriptUrl' class='solrPagerNext'>%MAKETEXT{\"Next\"}%</a>";
  } else {
    $result .= "<span class='solrPagerNext foswikiGrayText'>%MAKETEXT{\"Next\"}%</span>";
  }

  $result = "<div class='solrPager'>$result</div>" if $result;

  return $result;
}

=begin TML

---++ getACLFilter() -> $acl

returns a solr filter for the current user

=cut

sub getACLFilter {
  my $this = shift;

  my %users = ();

  $users{Foswiki::Func::getWikiName()} = 1;
  $users{$Foswiki::cfg{AdminUserWikiName}} = 1 if Foswiki::Func::isAnAdmin();
  $users{"all"} = 1;

  return "access_granted:(".join(" OR ", sort keys %users).")";
}

=begin TML

---++ restSOLRPROXY($web, $topic) -> 

implements the =proxy= REST endpoint. This basically is the most
unfiltered access to the Solr backend, only adding ACLs to any
query.

=cut

sub restSOLRPROXY {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};

  $theWeb ||= $this->{session}->{webName};
  $theTopic ||= $this->{session}->{topicName};
  my $params = $this->getRequestParams();
  my $theQuery = $params->{q} || "*:*";

  push @{$params->{fq}}, $this->getACLFilter();

  #$params->{bf} = 'recip(ms(NOW,date),3.16e-11,10,1)';

  #print STDERR "fq=$params->{fq}\n";

  my $response = $this->solrSearch($theQuery, $params);
  $this->writeEvent($theQuery);

  my $result = '';
  my $status = 200;
  my $contentType = "application/json; charset=utf8";

  try {
    $result = $this->getRawResponse($response);

  } catch Error::Simple with {
    $result = "Error parsing response";
    $status = 500;
    $contentType = "text/plain; charset=utf8";
  };

  $this->{session}->{response}->status($status);
  $this->{session}->{response}->header(-type=>$contentType);

  if (Foswiki::Func::getContext()->{"PiwikPluginEnabled"}) {
    my $count = 0;
    if ($result =~ /"numFound"\s*:\s*(\d+),/) {
      $count = $1;
    }
    require Foswiki::Plugins::PiwikPlugin;
    try {
      Foswiki::Plugins::PiwikPlugin::tracker->doTrackSiteSearch(
        $theQuery,
        $theWeb, # hm, there's no single category that makes sense here
        $count
      );
    } catch Error::Simple with {
      # report but ignore
      print STDERR "PiwikiPlugin::Tracker - ".shift()."\n";
    };
  }

  return $this->fromUtf8($result);
}

=begin TML

---++ restSOLRSEARCH($web, $topic)

=cut

sub restSOLRSEARCH {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $params = $this->getRequestParams();

  $theWeb ||= $this->{session}->{webName};
  $theTopic ||= $this->{session}->{topicName};

  my $theQuery = $params->{'q'} || $params->{search};

  # SMELL: why doesn't this work out directly?
  my $jsonWrf = delete $params->{"json.wrf"};

#  print STDERR "theQuery=$theQuery\n";

  my $response = $this->doSearch($theQuery, $params);

  # I feel lucky: redirect to first result
  my $theLucky = Foswiki::Func::isTrue($params->{'lucky'});
  if ($theLucky) {
    my $url = $this->getFirstUrl($response);
    if ($url) {
      # will redirect in finishPlugin handler
      $this->{redirectUrl} = $url;
      return "\n\n";
    }
  }

  my $result = '';
  my $status = 200;
  my $contentType = "application/json; charset=utf-8";

  try {
    $result = $this->getRawResponse($response);
  } catch Error::Simple with {
    $result = "Error parsing response";
    $status = 500;
    $contentType = "text/plain; charset=utf-8";
  };

  if ($jsonWrf) {
    $result = $jsonWrf."(".$result.")";
    $contentType = "text/javascript";
  }

  $this->{session}->{response}->status($status);
  $this->{session}->{response}->header(-type => $contentType);

  return $result;
}

=begin TML

---++ getFirstUrl($resonse) -> $url

=cut

sub getFirstUrl {
  my ($this, $response) = @_;

  my $url;

  if ($this->totalEntries($response)) {
    for my $doc ($response->docs) {
      $url = $doc->value_for("url");
      last if $url;
    }
  }

  return $url;
}

=begin TML

---++ restSOLRAUTOSUGGEST($web, $topic)

implements the =autosuggest= REST handler

=cut

sub restSOLRAUTOSUGGEST {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $params = $this->getRequestParams();

  my $theQuery = $params->{'term'} // '';
  $theQuery =~ s/^\s+|\s+$//g;

  # augment
# unless ($theQuery eq '' || $theQuery =~ /[\*\-"'\{\}:]/) {
#   #$theQuery = "$theQuery OR $theQuery* OR \"$theQuery\"";
#   $theQuery = "$theQuery OR $theQuery*";
# }

  my $theRaw = Foswiki::Func::isTrue(scalar $params->{raw});

  my $theLimit = $params->{limit};
  $theLimit = 5 unless defined $theLimit;

  my $theOffset = $params->{offset};
  $theOffset = 0 unless defined $theOffset;

  my $theFields = $params->{fields};
  $theFields = "container_title,title,thumbnail,url,score,field_Telephone_s,field_Phone_s,field_Mobile_s" unless defined $theFields;

  # make sure required fields are contained
  my %fields = map {$_ => 1} split(/\s*,\s*/, $theFields);
  $fields{type} = 1;
  $fields{name} = 1;
  $fields{web} = 1;
  $fields{topic} = 1;
  $theFields = join(",", sort keys %fields);

  my $theGroups = $params->{groups};
  $theGroups = 'persons, topics, other' unless defined $theGroups;

  my $userForm = $Foswiki::cfg{SolrPlugin}{PersonDataForm} || $Foswiki::cfg{PersonDataForm} || $Foswiki::cfg{Ldap}{PersonDataForm} || '*UserForm';
  my %filter = (
    persons => ["form:$userForm", "-state:disabled"],
    topics => ["type:(topic)", "-form:$userForm"],
    other => ["-type:(topic)"],
  );

  my @groupQuery = ();
  foreach my $group (split(/\s*,\s*/, $theGroups)) {
    my $filter = $filter{$group};
    next unless defined $filter;
    $filter = join(" ", @$filter) if ref($filter);
    push @groupQuery, $filter;
  }

  my @filter = ();

  my $trashWeb = $Foswiki::cfg{TrashWebName} || 'Trash';
  push @filter, "-web:_* -web:$trashWeb"; # exclude some webs 

  my $solrExtraFilter = Foswiki::Func::getPreferencesValue("SOLR_EXTRAFILTER");
  $solrExtraFilter = Foswiki::Func::expandCommonVariables($solrExtraFilter) 
    if defined $solrExtraFilter && $solrExtraFilter =~ /%/;
  push @filter, $solrExtraFilter 
    if defined $solrExtraFilter && $solrExtraFilter ne '';

  my $solrDefaultWeb = Foswiki::Func::getPreferencesValue("SOLR_DEFAULTWEB");
  $solrDefaultWeb = Foswiki::Func::expandCommonVariables($solrDefaultWeb) 
    if defined $solrDefaultWeb && $solrDefaultWeb =~ /%/;
  push @filter, "web:$solrDefaultWeb" 
    if defined $solrDefaultWeb && $solrDefaultWeb ne '';

  my $theFilter = $params->{filter};
  push @filter, $theFilter if defined $theFilter && $theFilter ne '';

  push @filter, $this->getACLFilter();

  my %params = (
    q => $theQuery,
    indent => "true",
    group => "true",
    fl => $theFields,
    "group.sort" => "score desc",
    "group.offset" => $theOffset,
    "group.limit" => $theLimit,
    "group.query" => \@groupQuery,
     fq => \@filter,
  );

  my $theQueryFields = $params->{queryfields} || "title_search^10, title^10, title_prefix^5, title_substr^2, summary^5, catchall, text_ws";
  $params{qf} = [split(/\s*,\s*/, $theQueryFields)];

  my $response = $this->solrSearch($theQuery, \%params);
  $this->writeEvent($theQuery);

  my $result = '';
  my $status = 200;
  my $contentType = "application/json; charset=utf-8";

  try {
    if ($theRaw) {
      $result = $this->getRawResponse($response);
    } else {
      $result = $response->content();
    }
  } catch Error::Simple with {
    $result = "Error parsing response: ".$this->getRawResponse($response);
    $status = 500;
    $contentType = "text/plain";
  };

  if ($status == 200 && !$theRaw) {
    my @autoSuggestions = ();
    my $group;

    if (Foswiki::Func::getContext()->{"PiwikPluginEnabled"}) {
      my $count = 0;
      foreach my $groupId (keys %{$result->{grouped}}) {
        $count += $result->{grouped}{$groupId}{doclist}{numFound};
      }
      require Foswiki::Plugins::PiwikPlugin;
      try {
        $theQuery =~ s/^\s+|\s+$//g;
        $theQuery =~ s/\s*\*//;
        Foswiki::Plugins::PiwikPlugin::tracker->doTrackSiteSearch(
          $theQuery,
          $theWeb, # hm, there's no single category that makes sense here
          $count
        );
      } catch Error::Simple with {
        # report but ignore
        print STDERR "PiwikiPlugin::Tracker - ".shift()."\n";
      };
    }

    # person topics
    my $key = join(" ", @{$filter{persons}});
    $group = $result->{grouped}{$key};
    if (defined $group) {
      my @docs = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        my $phoneNumber = $doc->{field_Telephone_s} || $doc->{field_Phone_s} || $doc->{field_Mobile_s};
        $doc->{phoneNumber} = $phoneNumber if defined $phoneNumber;

        $doc->{thumbnail} = $Foswiki::cfg{PubUrlPath}."/".$Foswiki::cfg{SystemWebName}."/JQueryPlugin/images/nobody.gif"
          unless defined $doc->{thumbnail};

        $doc->{container_title} = $this->translate($doc->{container_title}, $theWeb, $theTopic)
          if defined $doc->{container_title};

        push @docs, $doc;
      }
      push @autoSuggestions, {
        "group" => "persons",
        "start" => $group->{doclist}{start},
        "numFound" => $group->{doclist}{numFound},
        "docs" => \@docs,
        "moreUrl" => $this->getAjaxScriptUrl($Foswiki::cfg{UsersWebName}, $Foswiki::cfg{UsersTopicName}, {
          topic => $Foswiki::cfg{UsersTopicName},
          #fq => ..., # SMELL: what about the other filters
          search => $theQuery,
          origin => "$theWeb.$theTopic",
        })
      } if @docs;
    }

    # normal topics
    $key = join(" ", @{$filter{topics}});
    $group = $result->{grouped}{$key};
    if (defined $group) {
      my @docs = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        $doc->{thumbnail} //= $doc->{icon} // $this->mapToIconFileName("unknown");
        $doc->{container_title} = $this->translate($doc->{container_title}, $theWeb, $theTopic)
          if defined $doc->{container_title};
        push @docs, $doc;
      }
      push @autoSuggestions, {
        "group" => "topics",
        "start" => $group->{doclist}{start},
        "numFound" => $group->{doclist}{numFound},
        "docs" => \@docs,
        "moreUrl" => $this->getAjaxScriptUrl($this->{session}{webName}, 'WebSearch', {
          topic => 'WebSearch',
          fq => $filter{topics}, # SMELL: what about the other filters
          search => $theQuery,
          origin => "$theWeb.$theTopic",
        })
      } if @docs;
    }

    # other
    $key = join(" ", @{$filter{other}});
    $group = $result->{grouped}{$key};
    if (defined $group) {
      my @docs = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        unless (defined $doc->{thumbnail}) {
          if ($this->isImage($doc->{name})) {
            $doc->{thumbnail} = $doc->{name};
          } else {
            my $ext = $doc->{name};
            $ext =~ s/^.*\.([^\.]+)$/$1/g;
            $doc->{thumbnail} = $this->mapToIconFileName($ext);
          }
        }
        $doc->{container_title} = $this->translate($doc->{container_title}, $theWeb, $theTopic)
          if defined $doc->{container_title};
        push @docs, $doc;
      }
      push @autoSuggestions, {
        "group" => "other",
        "start" => $group->{doclist}{start},
        "numFound" => $group->{doclist}{numFound},
        "docs" => \@docs,
        "moreUrl" => $this->getAjaxScriptUrl($this->{session}{webName}, 'WebSearch', {
          topic => 'WebSearch',
          fq => $filter{other}, # SMELL: what about the other filters
          search => $theQuery,
          origin => "$theWeb.$theTopic",
        })
      } if @docs;
    }

    $result = JSON::to_json(\@autoSuggestions, {pretty => 1});
  }
  
  $this->{session}->{response}->status($status);
  $this->{session}->{response}->header(-type=>$contentType);

  return $result;
}

=begin TML

---++ restSOLRAUTOCOMPLETE($web, $topic)

implements the =autocomplete= REST handler

=cut

sub restSOLRAUTOCOMPLETE {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $params = $this->getRequestParams();

  my $theRaw = Foswiki::Func::isTrue($params->{raw});
  my $theQuery = $params->{term} // '';
  my $theFilter = $params->{filter};
  my $theEllipsis = Foswiki::Func::isTrue($params->{ellipsis});
  my $thePrefix;
  my $foundPrefix = 0;

  my @filter = $this->parseFilter($theFilter);
  push @filter, $this->getACLFilter();

  # tokenize here as well to separate query and prefix
  $theQuery =~ s/[\!"§\$%&\/\(\)=\?{}\[\]\*\+~#',\.;:\-_]/ /g;
  $theQuery =~ s/([$Foswiki::regex{lowerAlpha}])([$Foswiki::regex{upperAlpha}$Foswiki::regex{numeric}]+)/$1 $2/g;
  $theQuery =~ s/([$Foswiki::regex{numeric}])([$Foswiki::regex{upperAlpha}])/$1 $2/g;

  # work around solr not doing case-insensitive facet queries
  $theQuery = lc($theQuery);

  if ($theQuery =~ /^(.+) (.+?)$/) {
    $theQuery = $1;
    $thePrefix = $2;
    $foundPrefix = 1;
  } else {
    $thePrefix = $theQuery;
    $theQuery = '*:*';
  }

  my $field = $params->{field} || 'text';

  my $solrParams = {
    "facet.prefix" => $thePrefix,
    "facet" => 'true',
    "facet.mincount" => 1,
    "facet.limit" => ($params->{limit} || 10),
    "facet.field" => $field,
    "indent" => 'true',
    "rows" => 0,
  };
  $solrParams->{"fq"} = \@filter if @filter;

  my $response = $this->solrSearch($theQuery, $solrParams);

  if ($theRaw) {
    my $result = $this->getRawResponse($response)."\n\n";
    return $result;
  }
  $this->log($response->raw_response->content()) if TRACE;

  my $facets = $this->getFacets($response);
  return '' unless $facets;

  # format autocompletion
  my @result = ();
  foreach my $facet (keys %{$facets->{facet_fields}}) {
    my @facetRows = ();
    my @list = @{$facets->{facet_fields}{$facet}};
    while (my $key = shift @list) {
      my $freq = shift @list;
      $key = "$theQuery $key" if $foundPrefix;
      my $title = $key;
      if ($theEllipsis) {
        $title = $key;
        $title =~ s/$thePrefix $theQuery/.../;
      }
      my $line;

      $line = "{\"value\":\"$key\", \"label\":\"$title\", \"frequency\":$freq}";
      push(@result, $line);
    }
  }

  return "[\n".join(",\n ", @result)."\n]";
}

=begin TML

---++ restSOLRSIMILAR($web, $topic)

implements the =similar= REST handler

=cut

sub restSOLRSIMILAR {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $params = $this->getRequestParams();
  my $theQuery = delete $params->{q};
  $theQuery =  "id:$theWeb.$theTopic" unless defined $theQuery;

  my $response = $this->doSimilar($theQuery, $params);

  my $result = '';
  try {
    $result = $this->getRawResponse($response);
  } catch Error::Simple with {
    $result = "Error parsing result";
  };

  return $result."\n\n";
}

=begin TML

---++ handleSOLRSIMILAR($params, $web, $topic) -> $result

implements the =%SOLRSIMILAR= macro

=cut

sub handleSOLRSIMILAR {
  my ($this, $params, $theWeb, $theTopic) = @_;

  return $this->inlineError("can't connect to solr server") unless defined $this->{solr};

  my $theQuery = $params->{_DEFAULT};
  $theQuery = "id:$theWeb.$theTopic" unless defined $theQuery;

  my $response = $this->doSimilar($theQuery, $params);

  return $this->formatResponse($params, $theWeb, $theTopic, $response);
}


=begin TML

---++ doSimilar($query, $params) -> $response

=cut

sub doSimilar {
  my ($this, $query, $params) = @_;

  #$this->log("doSimilar($query)");

  my $theQuery = $query || $params->{'q'} || '*:*';
  my $theLike = $params->{'like'} // 'field_Category_flat_lst^5,tag';
  my $theFields = $params->{'fields'} // 'web,topic,title,score';
  my $theFilter = $params->{'filter'} // 'type:topic';
  my $theInclude = Foswiki::Func::isTrue($params->{'include'});
  my $theStart = $params->{'start'} || 0;
  my $theRows = $params->{'rows'} // 20;
  my $theBoost = Foswiki::Func::isTrue($params->{'boost'}, 1);
  my $theMinTermFreq = $params->{'mintermfrequency'};
  my $theMinDocFreq = $params->{'mindocumentfrequency'};
  my $theMinWordLength = $params->{'minwordlength'};
  my $theMaxWordLength = $params->{'maxwordlength'};
  my $theMaxTerms = $params->{'maxterms'} || 25;

  my @filter = $this->parseFilter($theFilter);
  push @filter, $this->getACLFilter();

  my $solrParams = {
    "q" => $theQuery, 
    "fq" => \@filter,
    "fl" => $theFields,
    "rows" => $theRows,
    "start" => $theStart,
    "indent" => 'true',
    "mlt.maxqt" => $theMaxTerms,
  };
  
  my @fields = ();
  my @boosts = ();
  foreach my $like (split(/\s*,\s*/, $theLike)) {
    if ($like =~ /^(.*)\^(.*)$/) {
      push(@fields, $1);
      push(@boosts, $like);
    } else {
      push(@fields, $like);
    }
  }

  $solrParams->{"mlt.fl"} = join(',', @fields) if @fields;
  $solrParams->{"mlt.boost"} = $theBoost?'true':'false';
  $solrParams->{"mlt.qf"} = join(' ', @boosts) if @boosts;
  $solrParams->{"mlt.interestingTerms"} = 'details' if $params->{format_interesting};
  $solrParams->{"mlt.match.include"} = $theInclude?'true':'false';
  $solrParams->{"mlt.mintf"} = $theMinTermFreq if defined $theMinTermFreq;
  $solrParams->{"mlt.mindf"} = $theMinDocFreq if defined $theMinDocFreq;
  $solrParams->{"mlt.minwl"} = $theMinWordLength if defined $theMinWordLength;
  $solrParams->{"mlt.maxwl"} = $theMaxWordLength if defined $theMaxWordLength;

  $this->getFacetParams($params, $solrParams);

  return $this->solrRequest('mlt', $solrParams); #SMELL: faceting on mlt is broken. see SOLR-7883
}

=begin TML

---++ doSearch($query, $params) -> $response

=cut

sub doSearch {
  my ($this, $query, $params) = @_;

  my $theRows = $params->{rows};
  my $theFields = $params->{fields} || '*,score';
  my $theQueryType = $params->{type} || 'edismax';
  my $theWeb = $params->{web};
  my $theFilter = $params->{filter} // '';
  my $theExtraFilter = $params->{extrafilter};
  my $theDisjunktiveFacets = $params->{disjunctivefacets} // '';
  my $theCombinedFacets = $params->{combinedfacets} // '';
  my $theBoostQuery = $params->{boostquery};
  my $theQueryFields = $params->{queryfields};
  my $thePhraseFields = $params->{phrasefields};
  my $theDebugQuery = Foswiki::Func::isTrue($params->{debugquery}, 0);

  my %disjunctiveFacets = map {$_ => 1} split(/\s*,\s*/, $theDisjunktiveFacets);
  my %combinedFacets = map {$_ => 1} split(/\s*,\s*/, $theCombinedFacets);

  my $theStart = $params->{start} || 0;

  my $theReverse = Foswiki::Func::isTrue($params->{reverse});
  my $theSort = $params->{sort};
  $theSort = Foswiki::Func::expandTemplate("solr::defaultsort") unless defined $theSort;
  $theSort = "score desc" unless $theSort;

  my @sort = ();
  foreach my $sort (split(/\s*,\s*/, $theSort)) {
    if ($sort =~ /^(.+) (desc|asc)$/) {
      push @sort, $1.' '.$2;
    } else {
      push @sort, $sort.' '.($theReverse?'desc':'asc');
    }
  }
  $theSort = join(", ", @sort);

  $theRows =~ s/[^\d]//g if defined $theRows;
  $theRows = Foswiki::Func::expandTemplate('solr::defaultrows') if !defined($theRows) || $theRows eq '';
  $theRows = 20 if !defined($theRows) || $theRows eq '';

  my $solrParams = {
    "indent" =>'on',
    "start" => $theStart,
    "rows" => $theRows,
    "fl" => $theFields,
    "sort" => $theSort,
    "qt" => $theQueryType, # one of the requestHandlers defined in solrconfig.xml
    "wt" => 'json',
  };

  $solrParams->{bq} = $theBoostQuery if $theBoostQuery;
  $solrParams->{qf} = [split(/\s*,\s*/, $theQueryFields)] if $theQueryFields;
  $solrParams->{pf} = $thePhraseFields if $thePhraseFields;
  $solrParams->{debugQuery} = "true" if $theDebugQuery;

  if (defined $params->{group} || defined $params->{groupfunction} || defined $params->{groupquery}) {
    $solrParams->{"group"} = "true";
    $solrParams->{"group.field"} = $params->{group} if defined $params->{group};
    $solrParams->{"group.func"} = $params->{groupfunc} if defined $params->{groupfunc};
    $solrParams->{"group.query"} = $params->{groupquery} if defined $params->{groupquery}; # SMELL: need to process groupquery to split it into an array?
    $solrParams->{"group.sort"} = $params->{groupsort} || 'score desc';
    $solrParams->{"group.limit"} = $params->{grouplimit} || 1;
    $solrParams->{"group.offset"} = $params->{groupoffset} if $params->{groupoffset};
    $solrParams->{"group.ngroups"} = "true";
  }

  my $theHighlight = Foswiki::Func::isTrue($params->{highlight});
  if ($theHighlight && $theRows > 0) {
    $solrParams->{"hl"} = 'true';
    $solrParams->{"hl.method"} = 'unified';
    $solrParams->{"hl.fl"} = 'text';
    $solrParams->{"hl.snippets"} = '2';
    $solrParams->{"hl.fragsize"} = '300';
    $solrParams->{"hl.mergeContignuous"} = 'true';
    $solrParams->{"hl.usePhraseHighlighter"} = 'true';
    $solrParams->{"hl.highlightMultiTerm"} = 'true';
    $solrParams->{"hl.alternateField"} = 'text';
    $solrParams->{"hl.maxAlternateFieldLength"} = '300';
  }

  my $theMoreLikeThis = Foswiki::Func::isTrue($params->{morelikethis});
  if ($theMoreLikeThis) {
    # TODO: add params to configure this 
    $solrParams->{"mlt"} = 'true';
    $solrParams->{"mlt.mintf"} = '1';
    $solrParams->{"mlt.fl"} = 'web,topic,title,type,category,tag';
    $solrParams->{"mlt.qf"} = 'web^100 category^10 tag^10 type^200';
    $solrParams->{"mlt.boost"} = 'true';
    $solrParams->{"mlt.maxqt"} = '100';
  }

  my $theSpellcheck = Foswiki::Func::isTrue($params->{spellcheck});
  if ($theSpellcheck) {
    $solrParams->{"spellcheck"} = 'true';
#    $solrParams->{"spellcheck.maxCollationTries"} = 1;
#    $solrParams->{"spellcheck.count"} = 1;
    $solrParams->{"spellcheck.maxCollations"} = 1;
#    $solrParams->{"spellcheck.extendedResults"} = 'true';
    $solrParams->{"spellcheck.collate"} = 'true';
  }

  my $theStats = $params->{stats};
  if (defined $theStats) {
    $solrParams->{"stats"} = 'true';
    $solrParams->{"stats.field"} = $theStats;
  }

  # get all facet params
  $this->getFacetParams($params, $solrParams);

  # create filter query
  my @filter;
  my @tmpFilter = $this->parseFilter($theFilter);
  my %seenDisjunctiveFilter = ();
  my %seenCombinedFilter = ();

  # gather different types of filters
  foreach my $item (@tmpFilter) {

    if ($item =~ /^(.*):(.*?)$/) {
      my $facetName = $1;
      my $facetValue = $2;

      # disjunctive
      if ($disjunctiveFacets{$facetName} || $this->isDateField($facetName)) {
	push(@{$seenDisjunctiveFilter{$facetName}}, $facetValue);
	next;
      }

      # combined
      if ($combinedFacets{$facetName}) {
	push(@{$seenCombinedFilter{$facetValue}}, $facetName);
	next;
      }
    }

    # normal
    push(@filter, $item);
  }

  # add filters for disjunctive filters
  @tmpFilter = ();
  foreach my $facetName (keys %seenDisjunctiveFilter) {
    # disjunctive facets that are also combined with each other, produce one big disjunction
    # gathered in tmpFilter before adding it to the overal @filter array
    if ($combinedFacets{$facetName}) {
      my $expr = join(" OR ", map { "$facetName:$_" } @{$seenDisjunctiveFilter{$facetName}});
      push(@tmpFilter, $expr); 
    } else {
      my $expr = "{!tag=$facetName}$facetName:(".join(" OR ", @{$seenDisjunctiveFilter{$facetName}}).")";
      push(@filter, $expr);
    }
  }
  push(@filter, "(".join(" OR ", @tmpFilter).")") if @tmpFilter;

  # add filters for combined filters
  foreach my $facetValue (keys %seenCombinedFilter) {
    my @expr = ();
    foreach my $facetName (@{$seenCombinedFilter{$facetValue}}) {
      push @expr, "$facetName:$facetValue";
    }
    push @filter, "(".join(" OR ", @expr).")";
  }

  if ($theWeb && $theWeb ne 'all') {
    $theWeb =~ s/\//\./g;
    push(@filter, "web:$theWeb");
  }

  # extra filter 
  push @filter, $this->parseFilter($theExtraFilter);
  push @filter, $this->getACLFilter();

  $solrParams->{"fq"} = \@filter if @filter;

  if (TRACE) {
    foreach my $key (sort keys %$solrParams) {
      my $val = $solrParams->{$key};
      if (ref($val)) {
        $val = join(', ', @$val);
      }
      $this->log("solrParams key=$key val=$val");
    }
  }

  # default query for standard request handler
  if (!$query) {
    if (!$theQueryType || $theQueryType eq 'standard' || $theQueryType eq 'lucene') {
      $query = '*:*';
    }
  }

  #$this->log("query=$query") if TRACE;
  my $response = $this->solrSearch($query, $solrParams);

  # TRACE raw response
  if (TRACE) {
    my $raw = $response->raw_response->content();
    #$raw =~ s/"response":.*$//s;
    $this->log("response: $raw");
  }


  return $response;
}

=begin TML

---++ solrSearch($query, $params) -> $response

low-level solr search request

=cut

sub solrSearch {
  my ($this, $query, $params) = @_;

  $params ||= {};
  $params->{'q'} = $query if $query;
  $params->{qt} ||= "edismax";

  $query = $params->{q} // '';
  $query =~ s/[\s\*:]+$//g;
  $query =~ s/^[\s\*:]+//g;

  return $this->solrRequest("select", $params);
}

=begin TML

---++ writeEvent($query)

write a log event of the search query

=cut

sub writeEvent {
  my ($this, $query) = @_;

  my $web = $this->{session}->{webName};
  my $topic = $this->{session}->{topicName};

  # log term 
  $this->{session}->logger->log( {
    level    => 'info',
    action   => 'search',
    webTopic => "$web.$topic",
    extra    => $query
  });
}

=begin TML

---++ getFacetParams($params, $solrParams) -> \%facets

=cut

sub getFacetParams {
  my ($this, $params, $solrParams) = @_;

  $solrParams ||= {};

  my $theFacets = $params->{facets};
  my $theFacetQuery = $params->{facetquery} // '';

  return $solrParams unless $theFacets || $theFacetQuery;

  my $theFacetLimit = $params->{facetlimit} // '';
  my $theFacetSort = $params->{facetsort} // '';
  my $theFacetOffset = $params->{facetoffset};
  my $theFacetMinCount = $params->{facetmincount};
  my $theFacetPrefix = $params->{facetprefix};
  my $theFacetContains = $params->{facetcontains};
  my $theFacetIgnoreCase = $params->{facetignorecase};
  my $theFacetMethod = $params->{facetmethod};
  my $theFacetMatches = $params->{facetmatches};
  my $theFacetExclude = $params->{facetexclude};


  # parse facet limit
  my %facetLimit;
  my $globalLimit;
  foreach my $limitSpec (split(/\s*,\s*/, $theFacetLimit)) {
    if ($limitSpec =~ /^(.*)=(.*)$/) {
      $facetLimit{$1} = $2;
    } else {
      $globalLimit = $limitSpec; 
    }
  }
  $solrParams->{"facet.limit"} = $globalLimit if defined $globalLimit;
  foreach my $facetName (keys %facetLimit) {
    $solrParams->{"f.".$facetName.".facet.limit"} = $facetLimit{$facetName};
  }

  # parse facet sort
  my %facetSort;
  my $globalSort;
  foreach my $sortSpec (split(/\s*,\s*/, $theFacetSort)) {
    if ($sortSpec =~ /^(.*)=(.*)$/) {
      my ($key, $val) = ($1, $2);
      if ($val =~ /^(count|index)$/) { 
        $facetSort{$key} = $val;
      } else {
        $this->log("Error: invalid sortSpec '$sortSpec' ... ignoring");
      }
    } else {
      if ($sortSpec =~ /^(count|index)$/) { 
        $globalSort = $sortSpec; 
      } else {
        $this->log("Error: invalid sortSpec '$sortSpec' ... ignoring");
      }
    }
  }
  $solrParams->{"facet.sort"} = $globalSort if defined $globalSort;
  foreach my $facetName (keys %facetSort) {
    $solrParams->{"f.".$facetName.".facet.sort"} = $facetSort{$facetName};
  }

  # general params
  # TODO: make them per-facet like sort and limit
  $solrParams->{"facet"} = 'true';
  $solrParams->{"facet.mincount"} = (defined $theFacetMinCount)?$theFacetMinCount:1;
  $solrParams->{"facet.offset"} = $theFacetOffset if defined $theFacetOffset;
  $solrParams->{"facet.prefix"} = $theFacetPrefix if defined $theFacetPrefix;
  $solrParams->{"facet.method"} = $theFacetMethod if defined $theFacetMethod;
  $solrParams->{"facet.contains"} = $theFacetContains if defined $theFacetContains;
  $solrParams->{"facet.matches"} = $theFacetMatches if defined $theFacetMatches;
  $solrParams->{"facet.contains.ignoreCase"} = (Foswiki::Func::isTrue($theFacetContains) ? "true" : "false") if defined $theFacetIgnoreCase;
  $solrParams->{"facet.excludeTerms"} = $theFacetExclude if defined $theFacetExclude;
  
  # gather all facets
  my $fieldFacets;
  my $dateFacets;
  my $queryFacets;
  
  foreach my $querySpec (split(/\s*,\s*/, $theFacetQuery)) {
    my ($facetLabel, $facetQuery) = parseFacetSpec($querySpec);
    if ($facetQuery =~ /^(.*?):(.*)$/) {
      push(@$queryFacets, "{!ex=$1 key=$facetLabel}$facetQuery");
    } else {
      push(@$queryFacets, "{!key=$facetLabel}$facetQuery");
    }
  }

  foreach my $facetSpec (split(/\s*,\s*/, $theFacets)) {
    my ($facetLabel, $facetID) = parseFacetSpec($facetSpec);
    #next if $facetID eq 'web' && $params->{web} && $params->{web} ne 'all';
    next if $facetID eq 'facetquery';
    if ($facetID =~ /^(tag|category)$/) {
      push(@$fieldFacets, "{!key=$facetLabel}$facetID");
    } elsif ($this->isDateField($facetID)) {
      push(@$dateFacets, "{!ex=$facetID, key=$facetLabel}$facetID");
    } else {
      push(@$fieldFacets, "{!ex=$facetID key=$facetLabel}$facetID");
    }
  }

  # date facets params
  # TODO: provide general interface to range facets
  if ($dateFacets) {
    $solrParams->{"facet.range"} = $dateFacets;
    $solrParams->{"facet.range.start"} = $params->{facetdatestart} || 'NOW/DAY-7DAYS';
    $solrParams->{"facet.range.end"} = $params->{facetdateend} || 'NOW/DAY+1DAYS';
    $solrParams->{"facet.range.gap"} = $params->{facetdategap} || '+1DAY';
    $solrParams->{"facet.range.other"} = $params->{facetdateother} || 'before';
    $solrParams->{"facet.range.hardend"} = 'true'; # TODO
  }

  $solrParams->{"facet.query"} = $queryFacets if $queryFacets;
  $solrParams->{"facet.field"} = $fieldFacets if $fieldFacets;

  return $solrParams;
}

=begin TML

---++ currentPage($response) -> $int

replaces buggy Data::Page interface

=cut

sub currentPage {
  my ($this, $response) = @_;

  my $rows = 0;
  my $start = 0;
  
  try {
    $rows = $this->entriesPerPage($response);
    $start = $response->content->{response}->{start} || 0;
  } catch Error::Simple with {
    # ignore
  };

  return POSIX::floor($start / $rows) if $rows;
  return 0;
}

=begin TML

---++ lastPage()

=cut

sub lastPage {
  my ($this, $response) = @_;
  
  my $rows = 0;
  my $total = 0;
  try {
    $rows = $this->entriesPerPage($response);
    $total = $this->totalEntries($response);
  } catch Error::Simple with {
    # ignore
  };

  return POSIX::ceil($total/$rows)-1 if $rows;
  return 0;
}

=begin TML

---++ entriesPerPage()

=cut

sub entriesPerPage {
  my ($this, $response) = @_;

  my $result = 0;
  try {
    $result = $response->content->{responseHeader}->{params}->{rows} || 0;
  } catch Error::Simple with {
    # ignore
  };

  return $result;
}

=begin TML

---++ totalEntries()

=cut

sub totalEntries {
  my ($this, $response) = @_;

  my $result = 0;

  try {
   $result = $response->content->{response}->{numFound} || 0;
  } catch Error::Simple with {
    # ignore
  };

  return $result;
}

=begin TML

---++ getQueryTime()

=cut

sub getQueryTime {
  my ($this, $response) = @_;

  my $result = 0;
  try {
    $result = $response->content->{responseHeader}->{QTime} || 0;
  } catch Error::Simple with {
    # ignore
  };

  return $result;
}

=begin TML

---++ getHighlights()

=cut

sub getHighlights {
  my ($this, $response) = @_;

  my %hilites = ();

  my $struct;
  try {
    $struct = $response->content->{highlighting};
  } catch Error::Simple with {
    #ignore
  };

  if ($struct) {
    foreach my $id (keys %$struct) {
      my $hilite = $struct->{$id}{text}; # TODO: use the actual highlight field
      next unless $hilite;
      $hilite = join(" ... ", @{$hilite});

      # bit of cleanup in case we only get half the comment
      $hilite =~ s/<!--//g;
      $hilite =~ s/-->//g;
      $hilites{$id} = $hilite;
    }
  }

  return \%hilites;
}

=begin TML

---++ getMoreLikeThis()

=cut

sub getMoreLikeThis {
  my ($this, $response) = @_;

  my $moreLikeThis = [];

  try {
    $moreLikeThis = $response->content->{moreLikeThis};
  } catch Error::Simple with {
    #ignore
  };

  return $moreLikeThis;
}

=begin TML

---++ getCorrection()

=cut

sub getCorrection {
  my ($this, $response) = @_;

  my $struct;

  try {
    $struct = $response->content->{spellcheck};
  } catch Error::Simple with {
    # ignore
  };

  return '' unless $struct;

  $struct = {@{$struct->{suggestions}}};
  return '' unless $struct;
  return '' if $struct->{correctlySpelled};

  my $correction = $struct->{collation};
  return '' unless $correction;

  #return $correction;
  return $correction;
}

=begin TML

---++ getFacets()

=cut

sub getFacets {
  my ($this, $response) = @_;

  my $struct = '';

  try {
    $struct = $response->content->{facet_counts};
  } catch Error::Simple with {
    # ignore
  };

  return $struct;
}

=begin TML

---++ getInterestingTerms()

=cut

sub getInterestingTerms {
  my ($this, $response) = @_;

  my $struct = '';
  
  try {
    $struct = $response->content->{interestingTerms};
  } catch Error::Simple with {
    # ignore
  };

  return $struct;
}

=begin TML

---++ getGroups()

=cut

sub getGroups {
  my ($this, $response, $group) = @_;

  return unless $group;

  my $struct;
  
  try {
    $struct = $response->content->{grouped}{$group};
  } catch Error::Simple with {
    # ignore
  };

  return $struct;
}

=begin TML

---++ parseFacetSpec()

=cut

sub parseFacetSpec {
  my ($spec) = @_;

  $spec =~ s/^\s+//g;
  $spec =~ s/\s+$//g;
  my $key = $spec;
  my $val = $spec;

  if ($spec =~ /^(.+)=(.+)$/) {
    $key = $1;
    $val = $2;
  }
  $key =~ s/ /_/g;

  return ($key, $val);
}

=begin TML

---++ handleSOLRSCRIPTURL()

=cut

sub handleSOLRSCRIPTURL {
  my ($this, $params, $web, $topic) = @_;

  return '' unless defined $this->{solr};

  my $cacheEntry;
  my $theId = $params->{id};
  my $theWeb = $this->{session}->{webName};
  my $theTopic = $params->{topic} || $this->{session}->{topicName};
  $params->{origin} //= $theWeb.".".$this->{session}->{topicName};

  $cacheEntry = $this->{cache}{$theId} if defined $theId;
  $params = {%{$cacheEntry->{params}}, %$params} if defined $cacheEntry;

  my $theAjax = Foswiki::Func::isTrue(delete $params->{ajax}, 1);
  ($web, $topic) = $this->normalizeWebTopicName($theWeb, $theTopic);
 
  my $result = '';
  if ($theAjax) {
     $result = $this->getAjaxScriptUrl($web, $topic, $params);
  } else {
    $result = $this->getScriptUrl($web, $topic, $params, $cacheEntry->{response});
  }

  return $result;
}

=begin TML

---++ getAjaxScriptUrl()

=cut

sub getAjaxScriptUrl {
  my ($this, $web, $topic, $params) = @_;

  my @anchors = ();

  # TODO: add multivalue and union params
  my %isUnion = map {$_=>1} split(/\s*,\s*/, $params->{union} // '');
  my %isMultiValue = map {$_=>1} split(/\s*,\s*/, $params->{multivalue} // '');

  foreach my $key (sort keys %$params) {
    next if $key =~ /^(date|start|sort|_RAW|union|multivalue|separator|topic|_DEFAULT|search|origin)$/;

    my $val  = $params->{$key};

    next if !defined($val) || $val eq '';

    if ($key eq 'fq') {
      if (ref($val)) {
        push @anchors, 'fq='.$_ foreach @$val;
      } else {
        push @anchors, 'fq='.$val;
      }
      next;
    }

    my @locals = ();
    my $locals = '';
    push @locals, "tag=".$key if $isUnion{$key} || $isMultiValue{$key};
    push @locals, "q.op=OR" if $isUnion{$key};
    $locals = '{!'.join(' ', @locals).'}' if @locals;;

    # If the field value has a space or a colon in it, wrap it in quotes,
    # unless it is a range query or it is already wrapped in quotes.
    if ($val =~ /[ :]/  && $val !~ /[\[\{]\S+ TO \S+[\]\}]/ && $val !~ /^["\(].*["\)]$/) {
      $val = '%22' . $val . '%22'; # already escaped
    }

    push @anchors, 'fq='.$locals.$key.':'.($isUnion{$key}?"($val)":$val);
  }

  my $theStart = $params->{start};
  push @anchors, 'start='.$theStart if $theStart;

  my $theSort = $params->{sort};
  push @anchors, 'sort='.$theSort if $theSort;

  my $theSearch = $params->{_DEFAULT} || $params->{search};
  push @anchors, 'q='.$theSearch if defined $theSearch;

  my ($webSearchWeb, $webSearchTopic) = Foswiki::Func::normalizeWebTopicName($web, $params->{topic} || 'WebSearch');

  my $url = Foswiki::Func::getScriptUrlPath($webSearchWeb, $webSearchTopic, 'view', origin => $params->{origin});
  # not using getScriptUrl() for anchors due to encoding problems

  my $theSep = $params->{separator} // '&';
  $url .= '#'.join($theSep, map {urlEncode($_)} @anchors) if @anchors;

  return $url;
}

=begin TML

---++ urlEncode()

=cut

sub urlEncode {
  my $text = shift;

  $text =~ s/([':&"])/sprintf('%%%02X',ord($1))/ge;
  $text =~ s/\s/%20/g;

  return $text;
}

=begin TML

---++ getScriptUrl($web, $topic, $params, $response, $start) -> $url

=cut

sub getScriptUrl {
  my ($this, $web, $topic, $params, $response, $start) = @_;

  my $theRows = $params->{rows};
  $theRows = Foswiki::Func::expandTemplate('solr::defaultrows') unless defined $theRows;
  $theRows = 20 if !defined($theRows) || $theRows eq '';

  my $theSort = $params->{sort};
  $theSort = Foswiki::Func::expandTemplate("solr::defaultsort") unless defined $theSort;
  $theSort = "score desc" unless defined $theSort;
  $theSort =~ s/^\s+//;
  $theSort =~ s/\s+$//;

  $start = $this->currentPage($response) unless defined $start;
  $start = 0 unless $start;

  my @urlParams = (
    start=>$start,
    rows=>$theRows,
    sort=>$theSort,
  );
  push(@urlParams, search => $params->{search}) if $params->{search};
  push(@urlParams, display => $params->{display}) if $params->{display};
  push(@urlParams, type => $params->{type}) if $params->{type};
  push(@urlParams, web => $params->{web}) if $params->{web};
  push(@urlParams, autosubmit => $params->{autosubmit}) if defined $params->{autosubmit};


  # SMELL: duplicates parseFilter 
  my $theFilter = $params->{filter} // '';
  $theFilter = $this->urlDecode($this->entityDecode($theFilter));
  while ($theFilter =~ /([^\s:]+?):((?:\[[^\]]+?\])|[^\s",]+|(?:"[^"]+?")),?/g) {
    my $field = $1;
    my $value = $2;
    if (defined $value) {
      $value =~ s/^"//;
      $value =~ s/"$//;
      $value =~ s/,$//;
      my $item;
      if ($value =~ /\s/ && $value !~ /^["\[].*["\]]$/) {
	#print STDERR "... adding quotes\n";
	$item = '$field:"$value"';
      } else {
	#print STDERR "... adding as is\n";
       	$item = '$field:$value';
      }

      $item =~ s/\$field/$field/g;
      $item =~ s/\$value/$value/g;
      push(@urlParams, filter=>$item);
    } else {
      push(@urlParams, filter=>$value); # SMELL what for?
    }
  }

  return Foswiki::Func::getScriptUrlPath($web, $topic, 'view', @urlParams);
}

=begin TML

---++ parseFilter($filter) -> @filter

=cut

sub parseFilter {
  my ($this, $filter) = @_; 

  my @filter = ();
  $filter ||= '';
  $filter = $this->urlDecode($this->entityDecode($filter));

  #print STDERR "parseFilter($filter)\n";

  while ($filter =~ /([^\s:]+?):((?:\[[^\]]+?\])|[^\s",\(]+|(?:"[^"]+?")|(?:\([^\)]+?\))),?/g) {
    my $field = $1;
    my $value = $2;
    $value =~ s/^"//;
    $value =~ s/"$//;
    $value =~ s/,$//;
    $value =~ s/\//\./g if $field eq 'web';
    #print STDERR "field=$field, value=$value\n";
    if ($value) {
      my $item;
      if ($value !~ /^\(/ && $value =~ /\s/ && $value !~ /^["\[].*["\]]$/) {
        $item = '$field:"$value"';
      } else {
       	$item = '$field:$value';
      }
      $item =~ s/\$field/$field/g;
      $item =~ s/\$value/$value/g;
      #print STDERR "... adding=$item\n";
      push(@filter, $item);
    }
  }

  return @filter;
}

=begin TML

---++ iterate($params, $callback)

performs a solr search and iterates over it

=cut

sub iterate {
  my ($this, $params, $callback) = @_;

  $this->log("called iterate") if TRACE;

  $params->{q} ||= "*";
  $params->{fl} ||= "web, topic";
  $params->{sort} ||= "webtopic_sort asc";
  $params->{limit} ||= 0;
  $params->{rows} ||= $params->{limit} || 1000;
  $params->{start} ||= 0;

  push @{$params->{fq}}, $this->getACLFilter();
  my $len = 0;

  do {
    my $response = $this->solrSearch(undef, $params);

    my @docs = $response->docs;
    my $numFound = $response->content->{response}->{numFound};
    $len = scalar(@docs);

    if ($callback) {
      foreach my $doc (@docs) {
        my $ret = &{$callback}($doc, $numFound);
        return if defined($ret) && !$ret;
      }
    }

    #print STDERR "start=$params->{start}, len=$len, limit=$params->{limit}\n";

    $params->{start} += $len;

  } while ($len > 0 && ($params->{limit} == 0 || $params->{start} < $params->{limit}));

  return;
}

=begin TML

---++ iterateFacet($field, $callback, $ignoreAccess)

performs a facet search and iterates over it

=cut

sub iterateFacet {
  my ($this, $field, $callback, $ignoreAccess) = @_;

  my @filter = ();
  push @filter, $this->getACLFilter() unless $ignoreAccess;

  my $len = 0;
  my $offset = 0;
  my $limit = 100;

  do {
    my $response = $this->solrSearch(
      "*",
      {
        "fl" => "none",
        "rows" => 0,
        "fq" => \@filter,
        "facet" => "true",
        "facet.field" => $field,
        "facet.method" => "enum",
        "facet.limit" => $limit,
        "facet.offset" => $offset,
        "facet.sort" => "index",
      }
    );

    my $facets = $this->getFacets($response);
    return unless $facets;

    my %facet = @{$facets->{facet_fields}{$field}};

    if ($callback) {
      while(my ($val, $count) = each %facet) {
        &{$callback}($val, $count);
      }
    }

    $len = scalar(keys %facet);
    $offset += $len;

  } while ($len >= $limit);

  return $offset;
}

=begin TML

---++ getListOfTopics($web) -> @topics

returns the list of all topics of a web using a solr iteration

=cut

sub getListOfTopics {
  my ($this, $web) = @_;

  my @topics = ();

  $this->iterate({
      q => "web:$web type:topic", 
      fl => "webtopic,topic", 
    },
    sub {
      my $doc = shift;
      my $topic = (defined $web) ? $doc->value_for("topic") : $doc->value_for("webtopic");
      push @topics, $topic;
    }
  );

  return @topics;
}

=begin TML

---++ getListOfWebs() -> @webs

returns all webs using a solr search 

=cut

sub getListOfWebs {
  my $this = shift;

  my @webs = ();
  $this->iterateFacet("web", sub {
    my ($val, $count) = @_;
    if ($count) {
      push @webs, $val if $count;
    } else {
      #$this->log("WARNING: found web=$val with count=$count ... index needs optimization");
    }
  }, 1);

  return @webs;
}

1;

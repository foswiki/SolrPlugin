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

package Foswiki::Plugins::SolrPlugin;

=begin TML

---+ package Foswiki::Plugins::SolrPlugin

base class to hook into the foswiki core

=cut

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Form ();
use Foswiki::Request();
use Foswiki::Plugins::JQueryPlugin();
use Error qw(:try);


BEGIN {
  # Backwards compatibility for Foswiki 1.1.x
  unless (Foswiki::Request->can('multi_param')) {
    no warnings 'redefine'; ## no critic
    *Foswiki::Request::multi_param = \&Foswiki::Request::param;
    use warnings 'redefine';
  }
}
  
our $VERSION = '9.11';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Enterprise Search Engine for Foswiki based on Solr';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our %searcher;
our %indexer;
our %hierarchy;
our @knownIndexTopicHandler = ();
our @knownIndexAttachmentHandler = ();

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

initialize the plugin, automatically called during the core initialization process

=cut

sub initPlugin {

  Foswiki::Plugins::JQueryPlugin::registerPlugin("SearchBox", 'Foswiki::Plugins::SolrPlugin::SearchBox');
  Foswiki::Plugins::JQueryPlugin::registerPlugin("AutoSuggest", 'Foswiki::Plugins::SolrPlugin::Autosuggest');

  Foswiki::Func::registerTagHandler('SOLRSEARCH', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRSEARCH($params, $theWeb, $theTopic);
  });


  Foswiki::Func::registerTagHandler('SOLRFORMAT', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRFORMAT($params, $theWeb, $theTopic);
  });


  Foswiki::Func::registerTagHandler('SOLRSIMILAR', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRSIMILAR($params, $theWeb, $theTopic);
  });

  Foswiki::Func::registerTagHandler('SOLRSCRIPTURL', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRSCRIPTURL($params, $theWeb, $theTopic);
  });

  Foswiki::Func::registerTagHandler('SOLRFIELDNAME', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    my $fieldName = $params->{_DEFAULT} || '';
    my $formName = $params->{form};
    my $defaultType = $params->{default};

    if (defined $formName) {
      my $formDef;
      my $error;
      try {
        $formDef = Foswiki::Form->new($session, $Foswiki::cfg{UsersWebName}, $formName);
      }
      catch Foswiki::OopsException with {
        my $e = shift;
        $error = "ERROR: cannot read form definition for $formName";
      };

      return "<span class='foswikiAlert'>$error</span>" if defined $error;
      my $fieldDef = $formDef->getField($fieldName);
      return "<span class='foswikiAlert'>ERROR: unknown field $fieldName</span>" unless defined $fieldDef;

      return getIndexer($session)->getSolrFieldNameOfFormfield($fieldDef, $defaultType);
    } else {
      return getIndexer($session)->getSolrFieldNameOfFormfield($fieldName, $defaultType);
    }
  });

  Foswiki::Func::registerRESTHandler('search', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRSEARCH($web, $topic);
    }, 
    authenticate => $Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} // 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('proxy', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRPROXY($web, $topic);
    },
    authenticate => $Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} // 0,
    validate => 0,
    http_allow => 'GET,POST',
  );


  Foswiki::Func::registerRESTHandler('similar', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRSIMILAR($web, $topic);
    },
    authenticate => $Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} // 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('autocomplete', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRAUTOCOMPLETE($web, $topic);
    },
    authenticate => $Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} // 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('autosuggest', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRAUTOSUGGEST($web, $topic);
    },
    authenticate => $Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} // 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('webHierarchy', sub {
      my $session = shift;

      return getWebHierarchy($session)->restWebHierarchy(@_);
    },
    authenticate => $Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} // 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('optimize', sub {
      my $session = shift;
      return getIndexer($session)->optimize();
    },
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('crawl', sub {
      my $session = shift;

      my $request = Foswiki::Func::getRequestObject();
      my $name = $request->param("name");
      my $mode = $request->param("mode");

      return getCrawler($session, $name)->crawl($mode);
    },
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  return 1;
}

=begin TML

---++ finishPlugin()

called when the current session is clearned up

=cut

sub finishPlugin {

  my $indexer = $indexer{$Foswiki::cfg{DefaultUrlHost}};
  $indexer->finish() if $indexer;

  my $searcher = $searcher{$Foswiki::cfg{DefaultUrlHost}};
  if ($searcher) {
    #print STDERR "searcher keys=".join(", ", sort keys %$searcher)."\n";
    my $url = $searcher->{redirectUrl};
    if ($url) {
      #print STDERR "found redirect $url\n";
      Foswiki::Func::redirectCgiQuery(undef, $url);
    }
    $searcher->finish();
  }

  @knownIndexTopicHandler = ();
  @knownIndexAttachmentHandler = ();

  undef $indexer{$Foswiki::cfg{DefaultUrlHost}};
  undef $searcher{$Foswiki::cfg{DefaultUrlHost}};
  undef $hierarchy{$Foswiki::cfg{DefaultUrlHost}};
}

=begin TML

---++ registerIndexTopicHandler(&sub) 

register a custom handler to the indexing process of a topic

=cut

sub registerIndexTopicHandler {
  push @knownIndexTopicHandler, shift;
}

=begin TML

---++ registerIndexAttachmentHandler(&sub) 

register a custom handler to the indexing process of an attachment

=cut

sub registerIndexAttachmentHandler {
  push @knownIndexAttachmentHandler, shift;
}

=begin TML

---++ getWebHierarchy($session) -> $webHierarchy

returns a singleton object for the web-hierarchy service

=cut

sub getWebHierarchy {

  my $handler = $hierarchy{$Foswiki::cfg{DefaultUrlHost}};
  unless ($handler) {
    require Foswiki::Plugins::SolrPlugin::WebHierarchy;
    $handler = $hierarchy{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::WebHierarchy->new(@_);
  }

  return $handler;
}

=begin TML

---++ getSearcher($session) -> $searcher

returns a singleton object of the solr search service

=cut

sub getSearcher {

  my $searcher = $searcher{$Foswiki::cfg{DefaultUrlHost}};
  unless ($searcher) {
    require Foswiki::Plugins::SolrPlugin::Search;
    $searcher = $searcher{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::Search->new(@_);
  }

  return $searcher;
}

=begin TML

---++ getIndexer($session) -> $indexer

returns a singleton object of the solr indexing service

=cut

sub getIndexer {

  my $indexer = $indexer{$Foswiki::cfg{DefaultUrlHost}};
  unless ($indexer) {
    require Foswiki::Plugins::SolrPlugin::Index;
    $indexer = $indexer{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::Index->new(@_);
  }

  return $indexer;
}

=begin TML

---++ getCrawler($session, $name) -> $crawler

returns a crawler object identified by the given name. Crawlers are defined in the
=$Foswiki::cfg{SolrPlugin}{Crawler}{$name}= hash. For example:

<verbatim>
$Foswiki::cfg{SolrPlugin}{Crawler}{files} = {
  source => 'file system',
  module => 'Foswiki::Plugins::SolrPlugin::Crawler::FileSystemCrawler',
  path => '/mnt/network', 
  excludePath => '\/\.~|\.(bak|old|swp)$|\/\.git$',
  includePath => '',
  depth => 0,
  followSymLinks => 1,
  urlTemplate => 'file://$filePath',
  throttle => 0,
};
</verbatim>

defines a filesystem crawler. The =module= parameter is the only required setting,
whereas the rest is free to be used by the crawler implementation itself.

=cut

sub getCrawler {
  my ($session , $name) = @_;

  throw Error::Simple("no crawler name") unless defined $name;
    
  my $params = $Foswiki::cfg{SolrPlugin}{Crawler}{$name};

  throw Error::Simple("unknown crawler $name") unless defined $params;

  my $module = $params->{module};
  my $path = $module . '.pm';
  $path =~ s/::/\//g;
  eval {require $path};
  throw Error::Simple($@) if $@;

  $params->{name} ||= $name;

  return $module->new($session, %$params);
}

=begin TML

---++ indexCgi($session)

entry point for the =solrindex= script

=cut

sub indexCgi {
  my $session = shift;

  # force command_line flag off, so we do not get absolute urls in expandMacros()
  my $context =Foswiki::Func::getContext();
  delete $context->{command_line};

  if ($ENV{FOSWIKI_LEAKTRACE}) {
    require Test::LeakTrace;
    print STDERR "### starting leak trace\n";

    Test::LeakTrace::leaktrace(sub {
      getIndexer($session)->index();
    });

    print STDERR "### done leak trace\n";
  } else {
    getIndexer($session)->index();
  }

  return;
}

=begin TML

---++ searchCgi($session)

entry point for the =solrsearch= script

=cut

sub searchCgi {
  my $session = shift;

  my $request = $session->{cgiQuery} || $session->{request};
  my $template = $Foswiki::cfg{SolrPlugin}{SearchTemplate} || 'System.SolrSearchView';

  my $result = Foswiki::Func::readTemplate($template);
  $result = Foswiki::Func::expandCommonVariables($result) if $result =~ /%/;
  $result = Foswiki::Func::renderText($result);

  $session->writeCompletePage($result, 'view');
}

=begin TML

---++ afterSaveHandler($text, $topic, $web, $error, $meta )

handler to update the solr index on every save process. Note, this
handler is only called when ={SolrPlugin}{EnableOnSaveUpdates}= is enabled.

=cut

sub afterSaveHandler {
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnSaveUpdates};

  my ($text, $topic, $web, $error, $meta) = @_;
  getIndexer()->afterSaveHandler($web, $topic, $meta, $text);
}

=begin TML

---++ afterUploadHandler(\%attrHash, $meta )

handler to update the solr index on every upload. Note, this
handler is only called when ={SolrPlugin}{EnableOnUploadUpdates}= is enabled.

=cut

sub afterUploadHandler {
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnUploadUpdates};
  getIndexer()->afterUploadHandler(@_);
}

=begin TML

---++ afterRenameHandler( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment )

handler to update the solr index on every rename process. Note, this
handler is only called when ={SolrPlugin}{EnableOnRenameUpdates}= is enabled.

=cut

sub afterRenameHandler {
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates};
  getIndexer()->afterRenameHandler(@_);
}

1;

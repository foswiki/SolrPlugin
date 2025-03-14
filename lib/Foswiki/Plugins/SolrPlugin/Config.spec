# ---+ Extensions
# ---++ SolrPlugin

# **STRING**
# Url where to find the solr server. The url has got the format <code>http://&lt;domain>:&lt;port>/solr/&lt;core></code>. 
# The default core name is <code>foswiki</code>. When you installed VirtualHostingContrib then use the virtual domain as the core name per convention, 
# e.g. <code>http://localhost:8983/solr/www.foswiki.org</code>
$Foswiki::cfg{SolrPlugin}{Url} = 'http://localhost:8983/solr/foswiki';

# **NUMBER CHECK='undefok'**
# default timeout in seconds for an HTTP transaction to the SOLR server 
$Foswiki::cfg{SolrPlugin}{Timeout} = 180;

# **NUMBER CHECK='undefok'**
# timeout in seconds for an HTTP transaction to the SOLR server issuing an "optimize" 
# action. This normally takes a lot longer than a normal request as all of the SOLR database
# is restructured with a lot of IO on the disk. 
$Foswiki::cfg{SolrPlugin}{OptimizeTimeout} = 600;

# **STRING CHECK='undefok'** 
# Url of the server to send updates to. Note, you will only need this setting
# in a solr setup with master-slave replication where all updates are sent to
# a single master which in turn replicates them to the clients. This setting
# will override any {Url} setting above.
$Foswiki::cfg{SolrPlugin}{UpdateUrl} = '';

# **STRING CHECK='undefok'** 
# Url of a slave server to get search results from.  Note, you will only
# need this server in a solr setup with master-slave replication.  This
# setting will override any {Url} setting above.
$Foswiki::cfg{SolrPlugin}{SearchUrl} = '';

# **STRING**
# Name of the Foswiki DataForm that will identify the currently being indexed topic as a user profile page.
$Foswiki::cfg{SolrPlugin}{PersonDataForm} = '*UserForm';

# **STRING CHECK='undefok'**
# Comma seperated list of webs to skip
$Foswiki::cfg{SolrPlugin}{SkipWebs} = 'TWiki, TestCases';

# **STRING CHECK='undefok'**
# List of topics to skip.
# Topics can be in the form of Web.MyTopic, or if you want a topic to be excluded from all webs just enter MyTopic.
# For example: Main.WikiUsers, WebStatistics
$Foswiki::cfg{SolrPlugin}{SkipTopics} = 'WebStatistics';

# **STRING CHECK='undefok'**
# List of attachments to skip                                                                                         
# For example: Web.SomeTopic.AnAttachment.txt, Web.OtherTopic.OtherAttachment.pdf 
# Note that neither metadata nor the content of the attachment is added to the index
$Foswiki::cfg{SolrPlugin}{SkipAttachments} = '';

# **BOOLEAN**
# Require authentication for the plugin's rest handlers
$Foswiki::cfg{SolrPlugin}{RequireAuthenticationForRest} = 0;

# **BOOLEAN**
# Update the index when a topic is created or save.
# If this flag is disabled, you will have to install a cronjob to update the index regularly.
$Foswiki::cfg{SolrPlugin}{EnableOnSaveUpdates} = 0;

# **BOOLEAN**
# Update the index whenever a file is attached to an existing topic. 
# If this flag is disabled, you will have to install a cronjob to update the index regularly.
$Foswiki::cfg{SolrPlugin}{EnableOnUploadUpdates} = 0;

# **BOOLEAN**
# Update the index whenever a topic is renamed or deleted.
# If this flag is disabled, you will have to install a cronjob to update the index regularly.
$Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates} = 0;

# **BOOLEAN EXPERT**
# If activated only the most recent author and the topic creator will be indexed. Otherwise
# the 10 most recent contributors will be indexed. Useful to speed up indexing.
$Foswiki::cfg{SolrPlugin}{SimpleContributors} = 0;

# **PERL EXPERT**
# List of supported languages. These are the locale IDs as supported for by the schema.xml configuration
# file for solr. For each language ID there's a text field named text_&lt;ID&gt; that will be filled
# with content in the appropriate language. A wiki page can be flagged to be in a specific language by
# setting the CONTENT_LANGUAGE preference variable. Default is the site's language as configured in {Site}{Locale}.
# Entries in the list below are key =&gt; value pairs mapping a cleartext language label to the used locale ID
# used in the schema.
$Foswiki::cfg{SolrPlugin}{SupportedLanguages} = {
  'ar' => 'ar', 'arabic' => 'ar',
  'bg' => 'bg', 'bulgarian' => 'bg',
  'ca' => 'ca', 'catalan' => 'ca',
  'cjk' => 'cjk', 'zh-cn' => 'cjk', 'zh-tw' => 'cjk', 'ko' => 'cjk', 'chinese' => 'cjk', 'korean' => 'cjk', 
  'ckb' => 'ckb', 'kurdish' => 'ckb',
  'cz' => 'cz', 'czech' => 'cz',
  'da' => 'da', 'danish' => 'da', 
  'de' => 'de', 'german' => 'de', 
  'el' => 'el', 'greek' => 'el',
  'en' => 'en', 'en-us' => 'en', 'en-gb' => 'en', 'english' => 'en', 
  'es' => 'es', 'spanish' => 'es', 
  'eu' => 'eu', 'basque' => 'eu',
  'fa' => 'fa', 'persian' => 'fa',
  'fi' => 'fi', 'finish' => 'fi', 
  'fr' => 'fr', 'french' => 'fr', 
  'ga' => 'ga', 'irish' => 'ga',
  'gl' => 'gl', 'galician' => 'gl',
  'hi' => 'hi', 'hindi' => 'hi',
  'hu' => 'hu', 'hungarian' => 'hu',
  'hy' => 'hy', 'armenian' => 'hy',
  'id' => 'id', 'indonesian' => 'id',
  'it' => 'it', 'italian' => 'it', 
  'ja' => 'ja', 'japanese' => 'ja',
  'lv' => 'lv', 'latvian' => 'lv',
  'nl' => 'nl', 'dutch' => 'nl', 
  'no' => 'no', 'norwegian' => 'no',
  'pt' => 'pt', 'pt-br' => 'pt', 'portuguese' => 'pt', 
  'ro' => 'ro', 'romanian' => 'ro',
  'ru' => 'ru', 'russian' => 'ru', 
  'sv' => 'sv', 'swedish' => 'sv', 
  'th' => 'th', 'thai' => 'th',
  'tr' => 'tr', 'turkish' => 'tr',
};

# **PATH LABEL="Mime-Types Filename" CHECK='emptyok undefok' EXPERT**
# Pathname to file that maps file suffixes to MIME types :
# This may be a different file than the one defined in {MimeTypesFileName}.
$Foswiki::cfg{SolrPlugin}{MimeTypesFileName} = '';

# **PERL H EXPERT**
# This setting is required to enable executing the solrsearch script from the bin directory
$Foswiki::cfg{SwitchBoard}{solrsearch} = {
  package => 'Foswiki::Plugins::SolrPlugin', 
  function => 'searchCgi', 
  context => { 'solrsearch' => 1 },
};

# **PERL H EXPERT**
$Foswiki::cfg{SwitchBoard}{solrindex} = {
  package => 'Foswiki::Plugins::SolrPlugin', 
  function => 'indexCgi', 
  context => { 'solrindex' => 1 },
};

1;

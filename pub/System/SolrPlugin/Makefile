FOSWIKI_ROOT?=~/foswiki/trunk/core
TARGET=\
  build \
  build/ajax-solr.js \
  build/ajax-solr-widgets.js \
  build/ajax-solr-init.js \
  build/solrplugin.css \
  build/pattern.css \
  build/solr-searchbox.js \
  build/wikiusers.js \
  build/wikiusers.css \
  build/jquery.autosuggest.js \
  build/jquery.autosuggest.css

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

AJAX_SOLR_SOURCE=\
  lib/Core.js \
  lib/Parameter.js \
  lib/ParameterStore.js \
  lib/ParameterHashStore.js \
  lib/AbstractManager.js \
  lib/AbstractWidget.js \
  lib/AbstractFacetWidget.js \
  lib/AbstractSpatialWidget.js \
  lib/AbstractSpellcheckWidget.js \
  lib/AbstractTextWidget.js \
  lib/Manager.jquery.js \
  lib/ajaxsolr.support.js \
  src/ajax-solr-helpers.uncompressed.js \
  src/ajax-solr-dictionary.uncompressed.js

AJAX_SOLR_WIDGETS_SOURCE=\
  src/widgets/AbstractJQueryWidget.uncompressed.js \
  src/widgets/AbstractJQueryFacetWidget.uncompressed.js \
  src/widgets/FacetFieldWidget.uncompressed.js \
  src/widgets/WebFacetWidget.uncompressed.js \
  src/widgets/ToggleWidget.uncompressed.js \
  src/widgets/ToggleFacetWidget.uncompressed.js \
  src/widgets/PagerWidget.uncompressed.js \
  src/widgets/AlphaPagerWidget.uncompressed.js \
  src/widgets/ResultsPerPageWidget.uncompressed.js \
  src/widgets/ResultWidget.uncompressed.js \
  src/widgets/SearchBoxWidget.uncompressed.js \
  src/widgets/CurrentSelectionWidget.uncompressed.js \
  src/widgets/SortWidget.uncompressed.js \
  src/widgets/TagCloudWidget.uncompressed.js \
  src/widgets/HierarchyWidget.uncompressed.js \
  src/widgets/SpellcheckWidget.uncompressed.js \
  src/widgets/PageLengthWidget.uncompressed.js

#.PHONY: git
#git:
#	git clone https://github.com/evolvingweb/ajax-solr.git git

build:
	@mkdir build

build/ajax-solr.uncompressed.js: Makefile $(AJAX_SOLR_SOURCE)
	@echo "generating ajax-solr.uncompressed.js"
	@$(CAT) $(AJAX_SOLR_SOURCE) > $@

build/ajax-solr-widgets.uncompressed.js: Makefile $(AJAX_SOLR_WIDGETS_SOURCE)
	@echo "generating ajax-solr-widgets.uncompressed.js"
	@$(CAT) $(AJAX_SOLR_WIDGETS_SOURCE) > $@

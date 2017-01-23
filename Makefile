WEBSERVICE_SOURCES= \
  lib/WebService/Solr.pm \
  lib/WebService/Solr/Document.pm \
  lib/WebService/Solr/Field.pm \
  lib/WebService/Solr/Query.pm \
  lib/WebService/Solr/Response.pm

all: $(WEBSERVICE_SOURCES)

git:
	git clone https://github.com/ilmari/webservice-solr.git

ifneq (,$(wildcard webservice-solr))
lib/WebService/%: webservice-solr/lib/WebService/%
	cp $^ $@
lib/WebService/Solr/%: webservice-solr/lib/WebService/Solr/%
	cp $^ $@
endif


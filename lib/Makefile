WEBSERVICE_SOURCES= \
  WebService/Solr.pm \
  WebService/Solr/Document.pm \
  WebService/Solr/Field.pm \
  WebService/Solr/Query.pm \
  WebService/Solr/Response.pm

all: $(WEBSERVICE_SOURCES)

git:
	git clone https://github.com/petdance/webservice-solr.git

# ifneq (,$(wildcard webservice-solr))
# WebService/%: webservice-solr/lib/WebService/%
#         cp $^ $@
# WebService/Solr/%: webservice-solr/lib/WebService/Solr/%
#         cp $^ $@
# endif


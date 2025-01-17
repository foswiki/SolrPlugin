JAVAC=javac
SOLRVERSION=5.5.5
SOLRPATH=/opt/solr-$(SOLRVERSION)
CLASSPATH=$(SOLRPATH)/dist/solr-core-$(SOLRVERSION).jar:$(SOLRPATH)/server/solr-webapp/webapp/WEB-INF/lib/lucene-core-$(SOLRVERSION).jar:$(SOLRPATH)/server/solr-webapp/webapp/WEB-INF/lib/lucene-analyzers-common-$(SOLRVERSION).jar

build/filters/RemoveTokenGapsFilter.class: src/RemoveTokenGapsFilterFactory.java
	$(JAVAC) -d build -cp $(CLASSPATH) $^

"use strict";!function(e){var r={fl:["id","web","topic","type","date","container_id","container_web","container_topic","container_title","container_url","icon","title","summary","name","url","comment","thumbnail","width","height","field_TopicType_lst","field_Category_link_lst","author_title"],qt:"edismax",hl:!0,"hl.method":"unified","hl.fl":"text","hl.snippets":2,"hl.fragsize":100,"hl.mergeContignuous":!0,"hl.usePhraseHighlighter":!0,"hl.highlightMultiTerm":!0,"hl.alternateField":"text","hl.maxAlternateFieldLength":100,rows:10};e((function(){var t,l,o=e("#solrSearch"),s=o.data("solrUrl"),a=e.extend({},r,o.data("solrParams")),i=o.data("moreFields"),g=o.data("extraFilter"),d=new AjaxSolr.Manager({solrUrl:s,servlet:""});for(var n in e(".solrFacetField").solrFacetFieldWidget(d),e(".solrWebFacetField").solrWebFacetWidget(d),e(".solrToggleFacet").solrToggleFacetWidget(d),e(".solrToggle").solrToggleWidget(d),e("#solrCurrentSelection").solrCurrentSelectionWidget(d),e("#solrSearchBox").solrSearchBoxWidget(d),e(".solrResultsPerPage").solrResultsPerPageWidget(d),e(".solrSearchHits").solrResultWidget(d),e(".solrPager").solrPagerWidget(d),e(".solrAlphaPager").solrAlphaPagerWidget(d),e(".solrSorting select").solrSortWidget(d),e(".solrTagCloud").solrTagCloudWidget(d),e(".solrHierarchy").solrHierarchyWidget(d),e(".solrSpellchecking").solrSpellcheckWidget(d),e(".solrPageLength").solrPageLengthWidget(d),d.setStore(new AjaxSolr.ParameterHashStore),d.store.exposed=["fq","q","start","sort","rows"],d.init(),a)"fl"!=n&&d.store.addByValue(n,a[n]);l={};for(var h=0,c=(t=(t=d.store.get("fl").val()||[]).concat(a.fl).concat(i)).length;h<c;h++)null!=t[h]&&(l[t[h]]=1);for(var u in t=[],l)t.push(u);d.store.addByValue("fl",t),g&&d.store.hidden.push("fq="+g),a.rows&&d.store.hidden.push("rows="+a.rows),d.doRequest()}))}(jQuery);

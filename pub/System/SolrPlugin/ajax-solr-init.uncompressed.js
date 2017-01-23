(function ($) {
"use strict";

  var defaults = {
    "fl": [
      "id",
      "web",
      "topic",
      "type",
      "date",
      "container_id",
      "container_web",
      "container_topic",
      "container_title",
      "container_url",
      "icon",
      "title",
      "summary",
      "name",
      "url",
      "comment",
      "thumbnail",
      "width",
      "height",
      "field_TopicType_lst",
      "field_Category_title_lst",
      "author"
    ],
    "qt": "edismax",
    "hl": true,
    "hl.fl": 'text',
    "hl.snippets": 2,
    "hl.fragsize": 300,
    "hl.mergeContignuous": true,
    "hl.usePhraseHighlighter": true,
    "hl.highlightMultiTerm": true,
    "hl.alternateField": "text",
    "hl.maxAlternateFieldLength": 300,
    "hl.useFastVectorHighlighter": true,
    "rows": 10
  };

  $(function () {

    var $solrSearch = $("#solrSearch"),
        solrUrl = $solrSearch.data("solrUrl"),
        solrParams = $.extend({}, defaults, $solrSearch.data("solrParams")),
        moreFields = $solrSearch.data("moreFields"),
        extraFilter = $solrSearch.data("extraFilter"),
        manager = new AjaxSolr.Manager({
          solrUrl: solrUrl,
          servlet: ''
        }),
        param, val, arr;

    $(".solrFacetField").solrFacetFieldWidget(manager);
    $(".solrWebFacetField").solrWebFacetWidget(manager);
    $(".solrToggleFacet").solrToggleFacetWidget(manager);
    $("#solrCurrentSelection").solrCurrentSelectionWidget(manager);
    $("#solrSearchBox").solrSearchBoxWidget(manager);
    $(".solrResultsPerPage").solrResultsPerPageWidget(manager);
    $(".solrSearchHits").solrResultWidget(manager);
    $(".solrPager").solrPagerWidget(manager);
    $("#solrSorting").solrSortWidget(manager);
    $(".solrTagCloud").solrTagCloudWidget(manager);
    $(".solrHierarchy").solrHierarchyWidget(manager);
    $(".solrSpellchecking").solrSpellcheckWidget(manager);

    manager.setStore(new AjaxSolr.ParameterHashStore());
    manager.store.exposed = [ 'fq', 'q', 'start', 'sort', 'rows' ];

    // init
    manager.init();

    for (var name in solrParams) {
      if (name != 'fl') {
        manager.store.addByValue(name, solrParams[name]);
      }
    }

    // remove duplicates
    param = manager.store.get("fl");
    val = param.val() || [];
    val = val.concat(solrParams.fl).concat(moreFields);
    arr = {};

    for (var i = 0, l = val.length; i < l; i++) {
      if (val[i] != undefined) {
        arr[val[i]] = 1;
      }
    }
    val = [];
    for (var key in arr) {
      val.push(key);
    }
    manager.store.addByValue("fl", val);
    

    if (extraFilter) {
      manager.store.hidden.push("fq="+extraFilter);
    }

    if (solrParams.rows) {
      manager.store.hidden.push("rows="+solrParams.rows);
    }

    manager.doRequest();
  });
})(jQuery);


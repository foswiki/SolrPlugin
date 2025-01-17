/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.ResultWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      maxHilite: 600,
      blockUi: '#solrSearch',
      firstLoadingMessage:'Loading ...',
      loadingMessage: '',
      displayAs: '.solrDisplay',
      defaultDisplay: 'list',
      dateFormat: 'dddd, Do MMMM YYYY, HH:mm',
      dictionary: 'default',
      enableScroll: true,
      scrollTarget: '.solrSearchHits',
      byteSuffix: ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB']
    },

    scrollIntoView: function() {
      var self = this,
          rect, elem;

      if (self.options.enableScroll) {
        elem = $(self.options.scrollTarget)[0];
        rect = elem.getBoundingClientRect();

        if (rect.top < 0) {
          elem.scrollIntoView({
            block: "start",
            inline: "nearest",
            behavior: "smooth"
          });
        }
      }
    },

    beforeRequest: function () {
      var self = this;

      if (self._isFirst) {
        $.blockUI({message:'<h1>'+_(self.options.firstLoadingMessage, self.options.dictionary)+'</h1>'});
      } else {
        $(self.options.blockUi).block({message:'<h1>'+_(self.options.loadingMessage, self.options.dictionary)+'</h1>'});
      }
    },

    // unused 
    getSnippet: function(data) {
      return data.text?data.text.substr(0, 300) + ' ...':'';
    },

    escapeHtml: function(text) {
      return $("<div />")
        .text(text)
        .html()
        .replace(/&lt;em&gt;/g, "<em>")
        .replace(/&lt;\/em&gt;/g, "</em>");
    },

    afterRequest: function () {
      var self = this,
          response = self.manager.response;

      //console.log("response=",response);
      if (self._isFirst) {
        self._isFirst = false;
        $.unblockUI();
      } else {
        $(self.options.blockUi).unblock();
      }

      if (!$("#solrSearch").is(":visible")) {
        $("#solrSearch").fadeIn();
      }

      // rewrite view urls
      $.each(response.response.docs, function(index,doc) {
        var containerWeb = doc.container_web,
            containerTopic = doc.container_topic;

        if (doc.type === "topic") {
          doc.url = foswiki.getScriptUrl("view", doc.web, doc.topic);
        }

        if (typeof(containerWeb) === 'undefined' || typeof(containerTopic) === 'undefined') {
          if (typeof(doc.container) !== 'undefined' && doc.container_id.match(/^(.*)\.(.*)$/)) {
            containerWeb = RegExp.$1;
            containerTopic = RegExp.$2;
          }
        }

        if (typeof(containerWeb) !== 'undefined' && typeof(containerTopic) !== 'undefined') {
          doc.container_url = foswiki.getScriptUrl("view", containerWeb, containerTopic);
        }
      });

      self.$target.html($("#solrHitTemplate").render(
        response.response.docs, {
          debug:function(msg) {
            console.log(msg||'',this);
            return "";
          },
          encodeURIComponent: function(text) {
            return encodeURIComponent(text);
          },
          getPubUrlPath: function(web, topic, file, params) {
            return foswiki.getPubUrlPath(web, topic, file, params);
          },
          getScriptUrlPath: function(script, web, topic, params) {
            return foswiki.getScriptUrlPath(script, web, topic, params);
          },
          getTemplateName: function() {
            var type,
                topicType = this.data.field_TopicType_lst || [],
                i, j, l, m,
                templateName;

            for (j = 0, m = this.data.type.length; j < m; j++) {
              type = this.data.type[j].replace(/%\d+/g, "");  // clean up errors in data

              if (type === 'file') {
                return "#solrHitTemplate_file";
              }

              for (i = 0, l = topicType.length; i < l; i++) {
                templateName = "#solrHitTemplate_"+topicType[i].replace(/[\s\(\)]+/g, "_");
                if ($(templateName).length) {
                  return templateName;
                }
              }

              if (type === 'topic') {
                return "#solrHitTemplate_topic";
              }

              if (type.match(/png|gif|jpe?g|tiff|bmp/)) {
                return "#solrHitTemplate_image";
              }

              templateName = "#solrHitTemplate_"+type;
              if ($(templateName).length) {
                 return templateName;
              }
            }

            return "#solrHitTemplate_misc";
          },
          renderList: function(fieldName, separator, limit) {
            var list = this.data[fieldName], result = '', lines;

            separator = separator || ', ';
            limit = limit || 10;

            if (list && list.length) {
              lines = [];
              $.each(list.sort().slice(0, limit), function(i, v) {
                lines.push(_(v, self.options.dictionary));
              });
              result += lines.join(separator);
              if (list.length > limit) {
                result += " ...";
              }
            }

            return result;
          },
          renderTopicInfo: function() {
            var data = this.data,
		cats = data.field_Category_link_lst,
                tags = data.tag,
                lines, result = '';

            if (cats && cats.length) {
              result += '<i class="fa fa-folder"></i>';
              lines = [];
              $.each(cats.sort().slice(0, 10), function(i, v) {
		lines.push(v);
              });
              result += lines.join(", ");
              if (cats.length > 10) {
                result += " ...";
              }
            }
            if (tags && tags.length) {
              if (cats && cats.length) {
                result += "<span class='solrSep'>&#124;</span>";
              }
              result += '<i class="fa fa-tag"></i>';
              result += tags.sort().slice(0, 10).join(", ");
              if (tags.length > 10) {
                result += " ...";
              }
            }

            return result;
          },
          getHilite: function(id) {
            var hilite, result = [];
            if (typeof(response.highlighting) === 'undefined') {
              return '';
            }
            hilite = response.highlighting[id];
            if (typeof(hilite) === 'undefined' || typeof(hilite.text) === 'undefined') {
              return '';
            } else {
              // manually truncate hilite results as solr doesnt seem to do the job using fragsize
              hilite.text.forEach(function(elem) {
                var text = self.escapeHtml(elem);
                result.push(text);
              });
              return result.join(' ... ');//.substring(0, self.options.maxHilite);
            }
          },
          getIcon: function(icon) {
            var cls = "solrHitIcon foswikiIcon jqIcon",
                match;

            icon = icon || "fa-file-o";

            if (icon.startsWith("http")) {
              return "<img src='"+icon+"' class='solrHitIcon' />";
            }

            if (match = icon.match(/^(.*?)\-/)) {
              cls += " " + match[1];
            }
            cls += " " + icon;

            return "<i class='"+cls+"'></i>";
          },
          formatDate: function(dateString, dateFormat) {

            // convert epoch seconds to iso date string
            if (/^\d+$/.test(dateString)) {
              if (dateString.length == 10) {
                dateString += "000";
              }
              dateString = (new Date(parseInt(dateString))).toISOString();
            }

            if (typeof(dateString) === 'undefined' || dateString == '' || dateString == '0' || dateString == '1970-01-01T00:00:00Z') {
              return "???";
            }

            return moment(dateString).format(dateFormat || self.options.dateFormat);
            //return moment(dateString).calendar();
          },
          formatBytes: function(num) {
            var magnitude = 0, suffix, len = self.options.byteSuffix.length,
                value = parseInt(num, 10);

            while (magnitude < len) {
              suffix = self.options.byteSuffix[magnitude];
              if (value < 1024) {
                break;
              }
              value = value / 1024;
              magnitude++;
            }
            value = Math.round(value * 100) / 100;
            return value + ' ' + suffix;
          },
          contains: function(arr, val) {
             return $.inArray(val, arr) >= 0;
          }
        }
      ));

      self.$target.trigger("update");
      self.scrollIntoView();
    },

    update: function() {
      var self = this,
          elem = $(self.options.displayAs).filter(":checked");

      self.$target.removeClass("solrSearchHitsList solrSearchHitsGrid");
      if ((self.options.defaultDisplay == 'list' && !elem.length) || elem.val() == 'list') {
        self.$target.addClass("solrSearchHitsList");
      } else {
        self.$target.addClass("solrSearchHitsGrid");
      }
    },

    init: function() {
      var self = this;

      self._super();
      $(self.options.displayAs).on("change", function() {
        self.update();
      });
      $(self.options.displayAs).filter("[value='"+self.options.defaultDisplay+"']").prop("checked", true);
      self._isFirst = true;

      self.update();
    }
  });


  AjaxSolr.Helpers.build("ResultWidget");

})(jQuery);

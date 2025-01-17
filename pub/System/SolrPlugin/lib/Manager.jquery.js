/**
 * @see http://wiki.apache.org/solr/SolJSON#JSON_specific_parameters
 * @class Manager
 * @augments AjaxSolr.AbstractManager
 */
AjaxSolr.Manager = AjaxSolr.AbstractManager.extend(
  /** @lends AjaxSolr.Manager.prototype */
  {
  executeRequest: function (servlet, string, handler) {
    var self = this;
    string = string || this.store.string();
    handler = handler || function (data) {
      self.handleResponse(data);
    };
    if (this.proxyUrl) {
      this.xhr = jQuery.post(this.proxyUrl, { query: string }, handler, 'json');
    }
    else {
      this.xhr = jQuery.ajax({
        url: this.solrUrl + servlet + '?' + string + '&wt=json',
        dataType: 'json',
        success: handler,
        error: function(xhr, status, error) {
          if (status !== 'abort') {
            throw(status);
          }
        }
      });
    }
  }
});

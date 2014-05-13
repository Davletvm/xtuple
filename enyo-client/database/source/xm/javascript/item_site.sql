/* Delete previously misnamed record */
delete from xt.js where js_context='xtuple' and js_type = 'item_site';

select xt.install_js('XM','ItemSite','xtuple', $$
  /* Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple.
     See www.xm.ple.com/CPAL for the full text of the software license. */

(function () {

  if (!XM.ItemSite) { XM.ItemSite = {}; }

  XM.ItemSite.isDispatchable = true;

  /**
    Return the current cost for a particular item site.
  */
  XM.ItemSite.cost = function (itemsiteId) {
    if (!XT.Data.checkPrivilege('ViewCosts')) { return null; }
    return plv8.execute('select itemcost(itemsite_id) as cost from itemsite where obj_uuid = $1;', [itemsiteId])[0].cost;
  };

  /** @private */
  var _fetch = function (recordType, query) {
    query = query || {};
    var data = Object.create(XT.Data),
      namespace = recordType.beforeDot(),
      type = recordType.afterDot(),
      customerId = null,
      accountId = -1,
      shiptoId,
      effectiveDate = new Date(),
      vendorId = null,
      limit = query.rowLimit ? 'limit ' + Number(query.rowLimit) : '',
      offset = query.rowOffset ? 'offset ' + Number(query.rowOffset) : '',
      clause,
      keySearch = false,
      extra = "",
      sql = 'select * ' +
            'from %1$I.%2$I  ' +
            'where {conditions} {extra}';

    /* Handle special parameters */
    if (query.parameters) {
      query.parameters = query.parameters.filter(function (param) {
        var result = false;

        /* Over-ride usual search behavior */
        if (param.keySearch) {
          keySearch = param.value;
          sql += ' and (number ~^ ${p1} or barcode ~^ ${p1}) ' +
                'union ' +
                'select %2$I.* ' +
                'from %1$I.%2$I  ' +
                ' join itemsite on itemsite_id=id ' +
                ' join itemalias on itemsite_item_id=itemalias_item_id ' +
                '   and itemalias_crmacct_id is null ' +
                'where {conditions} {extra} ' +
                ' and (itemalias_number ~^ ${p1}) ' +
                'union ' +
                'select %2$I.* ' +
                'from %1$I.%2$I  ' +
                ' join itemsite on itemsite_id=id ' +
                ' join itemalias on itemsite_item_id=itemalias_item_id ' +
                '   and itemalias_crmacct_id={accountId} ' +
                'where {conditions} {extra} ' +
                ' and (itemalias_number ~^ ${p1}) ';
          return false;
        }

        switch (param.attribute)
        {
        case "customer":
          customerNumber = param.value;
          customerId = data.getId(data.fetchOrm('XM', 'CustomerProspectRelation'), param.value);
          accountId = data.getId(data.fetchOrm('XM', 'AccountRelation'), param.value);
          break;
        case "shipto":
          shiptoId = data.getId(data.fetchOrm('XM', 'CustomerShipto'), param.value);
          break;
        case "effectiveDate":
          effectiveDate = param.value;
          break;
        case "vendor":
          vendorId = data.getId(data.fetchOrm('XM', 'VendorRelation'), param.value);
          break;
        default:
          result = true;
        }
        return result;
      });
    }

    clause = data.buildClause(namespace, type, query.parameters, query.orderBy);

    /* If customer passed, restrict results to item sites allowed to be sold to that customer */
    if (customerId) {
      extra += ' and (item).id in (' +
             'select item_id from item where item_sold and not item_exclusive ' +
             'union ' +
             'select item_id from xt.custitem where cust_id=${p2} ' +
             '  and ${p4}::date between effective and (expires - 1) ';

      if (shiptoId) {
        extra += 'union ' +
               'select item_id from xt.shiptoitem where shipto_id=${p3}::integer ' +
               '  and ${p4}::date between effective and (expires - 1) ';
      }

      extra += ") ";
    }

    /* If vendor passed, and vendor can only supply against defined item sources, then restrict results */
    if (vendorId) {
      extra +=  ' and (item).id in (' +
              '  select itemsrc_item_id ' +
              '  from itemsrc ' +
              '  where itemsrc_active ' +
              '    and itemsrc_vend_id=' + vendorId + ')';
    }

    sql = XT.format(
      sql += '{orderBy} %3$s %4$s;',
      [namespace.decamelize(), type.decamelize(), limit, offset]
    );

    /* Query the model */
    sql = sql.replace(/{conditions}/g, clause.conditions)
             .replace(/{extra}/g, extra)
             .replace('{orderBy}', clause.orderBy)
             .replace('{limit}', limit)
             .replace('{offset}', offset)
             .replace('{accountId}', accountId)
             .replace(/{p1}/g, clause.parameters.length + 1)
             .replace(/{p2}/g, clause.parameters.length + (keySearch ? 2 : 1))
             .replace(/{p3}/g, clause.parameters.length + (keySearch ? 3 : 2))
             .replace(/{p4}/g, clause.parameters.length + (keySearch ? 4 : 3));

    if (keySearch) {
      clause.parameters.push(keySearch);
    }
    if (customerId) {
      clause.parameters = clause.parameters.concat([customerId, shiptoId, effectiveDate]);
    }
    if (DEBUG) {
      XT.debug('ItemSiteListItem sql = ', sql.slice(0,500));
      XT.debug('ItemSiteListItem sql = ', sql.slice(500, 1000));
      XT.debug('ItemSiteListItem sql = ', sql.slice(1000, 1500));
      XT.debug('ItemSiteListItem sql = ', sql.slice(1500, 2000));
      XT.debug('ItemSiteListItem parameters = ', clause.parameters);
    }
    return plv8.execute(sql, clause.parameters);
  };

  if (!XM.ItemSiteListItem) { XM.ItemSiteListItem = {}; }

  XM.ItemSiteListItem.isDispatchable = true;

  /**
    Returns item site list items using usual query means with additional special support for:
      * Attributes `customer`,`shipto`, and `effectiveDate` for exclusive item rules.
      * Attribute `vendor` to filter on only items with associated item sources.
      * Cross check on `alias` and `barcode` attributes for item numbers.

    @param {String} Record type. Must have `itemsite` or related view as its orm source table.
    @param {Object} Additional query filter (Optional)
    @returns {Array}
  */
  XM.ItemSiteListItem.fetch = function (query) {
    return _fetch("XM.ItemSiteListItem", query);
  };

  /**
   Wrapper for XM.ItemSiteListItem.fetch with support for REST query formatting.
   Sample usage:
    select xt.post($${
      "nameSpace":"XM",
      "type":"ItemSiteListItem",
      "dispatch":{
        "functionName":"restFetch",
        "parameters":[
          {
            "query":[
              {"customer":{"EQUALS":"TTOYS"}},
              {"shipto":{"EQUALS":"1d103cb0-dac6-11e3-9c1a-0800200c9a66"}},
              {"effectiveDate":{"EQUALS":"2014-05-01"}}
            ]
          }
        ]
      },
      "username":"admin",
      "encryptionKey":"hm6gnf3xsov9rudi"
    }$$);

   @param {Object} options: query
   @returns Object
  */
  XM.ItemSiteListItem.restFetch = function (options) {
    options = options || {};

    var items = {},
      query = {},
      result = {};

    if (options) {
      /* Convert from rest_query to XM.Model.query structure. */
      query = XM.Model.restQueryFormat(options);

      /* Perform the query. */
      items = XM.ItemSiteListItem.fetch(query);
    }

    result = {items: items};

    return items;
  };
  XM.ItemSiteListItem.restFetch.description = "Returns ItemSiteListItems with additional special support for exclusive item rules, to filter on only items with associated item sources and Cross check on `alias` and `barcode` attributes for item numbers.";
  XM.ItemSiteListItem.restFetch.request = {
    "$ref": "ItemSiteListItemQuery"
  };
  XM.ItemSiteListItem.restFetch.parameterOrder = ["options"];
  // For JSON-Schema deff, see:
  // https://github.com/fge/json-schema-validator/issues/46#issuecomment-14681103
  XM.ItemSiteListItem.restFetch.schema = {
    ItemSiteListItemQuery: {
      properties: {
        attributes: {
          title: "ItemSiteListItem Service request attributes",
          description: "An array of attributes needed to perform a ItemSiteListItem query.",
          type: "array",
          items: [
            {
              title: "Options",
              type: "object",
              "$ref": "ItemSiteListItemOptions"
            }
          ],
          "minItems": 1,
          "maxItems": 1,
          required: true
        }
      }
    },
    ItemSiteListItemOptions: {
      properties: {
        query: {
          title: "query",
          description: "The query to perform.",
          type: "array",
          items: [
            {
              title: "column",
              type: "object"
            }
          ],
          "minItems": 1
        },
        orderby: {
          title: "Order By",
          description: "The query order by.",
          type: "array",
          items: [
            {
              title: "column",
              type: "object"
            }
          ]
        },
        rowlimit: {
          title: "Row Limit",
          description: "The query for paged results.",
          type: "integer"
        },
        maxresults: {
          title: "Max Results",
          description: "The query limit for total results.",
          type: "integer"
        },
        pagetoken: {
          title: "Page Token",
          description: "The query offset page token.",
          type: "integer"
        },
        count: {
          title: "Count",
          description: "Set to true to return only the count of results for this query.",
          type: "boolean"
        }
      }
    }
  };

  if (!XM.ItemSiteRelation) { XM.ItemSiteRelation = {}; }

  XM.ItemSiteRelation.isDispatchable = true;

  /**
    Returns item site relatinos using usual query means with additional special support for:
      * Attributes `customer`,`shipto`, and `effectiveDate` for exclusive item rules.
      * Attribute `vendor` to filter on only items with associated item sources.
      * Cross check on `alias` and `barcode` attributes for item numbers.

    @param {String} Record type. Must have `itemsite` or related view as its orm source table.
    @param {Object} Additional query filter (Optional)
    @returns {Array}
  */
  XM.ItemSiteRelation.fetch = function (query) {
    return _fetch("XM.ItemSiteRelation", query);
  };

}());

$$ );


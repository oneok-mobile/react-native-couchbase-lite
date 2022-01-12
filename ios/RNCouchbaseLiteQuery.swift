//
//  RNCouchbaseLiteQuery.swift
//  RNCouchbaseLite
//
//  Created by Jordan Alcott on 8/17/21.
//
//

import Foundation
import CouchbaseLiteSwift


extension RNCouchbaseLite {
	class Query: NSObject {

	
		// -------------------------------------------------------------------------------------------
		// ---- Build & Execute Query ----------------------------------------------------------------

		// ---- Get Documents ------------------------------
		static func getDocuments(request: NSDictionary) throws -> [NSDictionary] {

			// From
			let (fromSource, fromDatabase, fromAlias) = try openSource(request["from"] as? String)

			// Join
			let joinExpressions = try buildJoinExpressions(request["join"] as? NSDictionary ?? [:])

			// Select
			let (selectExpressions, selectAll) = try buildSelectColumns(columns: request["select"] as? [String], defaultSource: fromAlias)

			// Where
			let whereExpression = try buildWhereExpression(whereClause: request["where"] as? [NSDictionary], defaultSource: fromAlias)

			// Group By
			let groupExpressions = try buildGroupExpressions(request["groupBy"] as? [String], defaultSource: fromAlias)

			// Order By
			let orderExpressions = try buildOrderExpressions(request["orderBy"] as? [String], defaultSource: fromAlias)


			// Query
			let query = QueryBuilder
			.select(selectExpressions)
			.from(fromSource)
			.join(joinExpressions)
			.where(whereExpression)
			.groupBy(groupExpressions)
			.orderBy(orderExpressions)

			// Limit
			var limitedQuery : Limit? = nil
			let limit: Int? = request["limit"] as? Int, offset: Int? = request["offset"] as? Int
			if limit != nil && limit! > 0 {
				limitedQuery = query.limit(Expression.int(limit!), offset: (offset != nil ? Expression.int(offset!) : nil))
			}

			// Execute
			var results : [Result]
			if limitedQuery != nil {
				results = try limitedQuery!.execute().allResults()
			}
			else {
				results = try query.execute().allResults()
			}
			var resultCollection : [NSDictionary]
			if selectAll {
				resultCollection = results.map { (document) -> NSDictionary in
					let dataKey = fromAlias != nil ? fromAlias! : fromDatabase.name
					return (document.toDictionary()[dataKey] as! NSDictionary)
				}
			}
			else {
				resultCollection = results.map { (document) -> NSDictionary in
					return document.toDictionary() as NSDictionary
				}
			}
			return resultCollection
		}


		// ---- Open Source --------------------------------
		static func openSource(_ from: String?) throws -> (DataSourceProtocol, CouchbaseLiteSwift.Database, String?) {

			if (from != nil) {
				let (databaseName, alias) = parseAlias(from!)
				let databaseConnection = try Database.getConnection(["databaseName": databaseName])
				let source = DataSource.database(databaseConnection.database!)
				if alias != nil {
					return (source.as(alias!), databaseConnection.database!, alias)
				}
				return (source, databaseConnection.database!, alias);
			}
			let databaseConnection = try Database.getConnection([:])
			return (DataSource.database(databaseConnection.database!), databaseConnection.database!, nil)
		}


		// ---- Columns ------------------------------------
		static func buildSelectColumns(columns: [String]?, defaultSource: String? = nil) throws -> ([SelectResultProtocol], Bool) {

			// Select
			var selectColumns : [SelectResultProtocol] = [SelectResult.all()]; // SELECT *
			var selectAll = true
			if (columns != nil) {
				selectAll = false
				selectColumns = try columns!.map { (_columnName) -> SelectResultProtocol in

					let (columnName, alias) = parseAlias(_columnName)
					let expression = try buildExpression(columnName, defaultCommand: "PROPERTY", defaultSource: defaultSource)
					if alias != nil {
						return SelectResult.expression(expression).as(alias!)
					}
					return SelectResult.expression(expression)

				}
			}
			return (selectColumns, selectAll);
		}


		// ---- Group Expressions --------------------------
		static func buildGroupExpressions(_ _groups: [String]?, defaultSource: String? = nil) throws -> [ExpressionProtocol] {

			let groups : [String] = _groups ?? []
			return try groups.map { (groupExpressionString) -> ExpressionProtocol in
				return try buildExpression(groupExpressionString, defaultCommand: "PROPERTY", defaultSource: defaultSource)
			}
		}


		// ---- Order Expressions --------------------------
		static func buildOrderExpressions(_ _order: [String]?, defaultSource: String? = nil) throws -> [OrderingProtocol] {

			let order : [String] = _order ?? []
			let orderExpressions : [OrderingProtocol] = try order.map { (_orderExpressionString) -> OrderingProtocol in

				let expressionParts = _orderExpressionString.split(separator: ">", maxSplits: 1)
				var orderExpressionString = _orderExpressionString, direction : String? = nil
				if expressionParts.count > 1 {
					orderExpressionString = String(expressionParts[0]);
					direction = String(expressionParts[1])
				}

				let orderExpression = Ordering.expression(try buildExpression(orderExpressionString, defaultCommand: "PROPERTY", defaultSource: defaultSource))
				if direction?.uppercased() == "DESCENDING" || direction?.uppercased() == "DESC" {
					return orderExpression.descending()
				}
				return orderExpression
			}
			return orderExpressions
		}


		// ---- Join Expressions ---------------------------
		static func buildJoinExpressions(_ joins: NSDictionary) throws -> [JoinProtocol] {

			var joinExpressions : [JoinProtocol] = []
			try joins.allKeys.forEach { (joinSourceKey) in
				let sourceKey = joinSourceKey as! String
				let (joinSource, _, joinAlias) = try openSource(sourceKey)
				let joinExpression = Join.leftJoin(joinSource).on(try buildWhereExpression(whereClause: joins[sourceKey] as? [NSDictionary], defaultSource: joinAlias))
				joinExpressions.append(joinExpression)
			}
			return joinExpressions
		}


		// ---- Where Expression ---------------------------
		static func buildWhereExpression(whereClause: [NSDictionary]?, defaultSource: String? = nil) throws -> ExpressionProtocol {

			// Assemble 'OR' Groups
			var ors : [ExpressionProtocol] = []
			if whereClause != nil {
				ors = try buildCompareExpressions(specifications: whereClause, defaultSource: defaultSource)
			}

			// Build Where Expression
			var whereExpression : ExpressionProtocol = Expression.all().equalTo(Expression.all()) // where * = *
			var orCount = 0
			ors.forEach { (orBlock) in
				orCount += 1
				if orCount == 1 {
					whereExpression = orBlock;
				}
				else {
					whereExpression = whereExpression.or(orBlock)
				}
			}
			return whereExpression;
		}


		// ---- Comparison Expressions ---------------------
		static func buildCompareExpressions(specifications: [NSDictionary]?, defaultSource: String? = nil) throws -> [ExpressionProtocol] {

			var expressions : [ExpressionProtocol] = []
			if specifications == nil {
				return expressions;
			}

			try specifications!.forEach { (specification : NSDictionary) in
				var ands = 0
				var currentExpression : ExpressionProtocol = Expression.all().equalTo(Expression.all()) // where * = *
				try specification.allKeys.forEach { (key) in
					ands += 1
					let keyString = key as! String;
					if ands == 1 {
						currentExpression = try buildCompareExpression(keyString: keyString, specification: specification, defaultSource: defaultSource)
					}
					else {
						currentExpression = currentExpression.and(try buildCompareExpression(keyString: keyString, specification: specification, defaultSource: defaultSource))
					}
				}
				expressions.append(currentExpression)
			}
			return expressions;
		}


		// ---- Comparison Expressions ---------------------
		static func buildCompareExpression(keyString: String, specification: NSDictionary, defaultSource: String? = nil) throws -> ExpressionProtocol {

			// Left-Side
			var leftExpression = try buildExpression(keyString, defaultCommand: "PROPERTY", defaultSource: defaultSource)


			// Right-Side, Non-String Values
			let _valueStringA = specification[keyString] as? String
			if (_valueStringA == nil) {
				return leftExpression.equalTo(Expression.value(specification[keyString]))
			}

			// Right-Side, String-Encoded Values
			let (valueString, comparator) = parseComparator(_valueStringA!)
			let allComparators = ["CONTAINS[]", "ARRAY_CONTAINS", "CONTAINS", "EQUALTO", "GT", ">", "GTE", ">=", "IN", "IS", "ISNOT", "!IS", "ISNULL", "ISNULLORMISSING", "LT", "<", "LTE", "<=", "LIKE", "NOTEQUALTO", "!", "NOTNULL", "NOTNULLORMISSING", "!ISNULL", "REGEX"]
			let isValidComparator = allComparators.contains((comparator ?? "").uppercased())
			let isLeftSideOnlyComparator = ["ISNULL", "ISNULLORMISSING", "NOTNULL", "NOTNULLORMISSING", "!ISNULL"].contains((comparator ?? "").uppercased())
			if !isValidComparator || (!isLeftSideOnlyComparator && valueString.count == 0) {
				return leftExpression.equalTo(try buildExpression(_valueStringA!, defaultSource: defaultSource))
			}
			let rightExpression = try buildExpression(valueString, defaultSource: defaultSource)


			// Comparator
			switch (comparator ?? "").uppercased() {

			case "CONTAINS[]", "ARRAY_CONTAINS":
				return ArrayFunction.contains(leftExpression, value: rightExpression)

			case "CONTAINS": // check if string has substring
				return Function.contains(leftExpression, substring: rightExpression)

			case "GT", ">":
				return leftExpression.greaterThan(try buildExpression(valueString, defaultCommand: "DOUBLE", defaultSource: defaultSource))

			case "GTE", ">=":
				return leftExpression.greaterThanOrEqualTo(try buildExpression(valueString, defaultCommand: "DOUBLE", defaultSource: defaultSource))

			case "IN":
				leftExpression = try buildExpression(keyString, defaultCommand: "PROPERTY", defaultSource: defaultSource) // Default to STRING
				let values = try valueString.split(separator: ",").map { (propNameB) -> ExpressionProtocol in
					return try buildExpression(String(propNameB), defaultCommand: "INT64", defaultSource: defaultSource)
				}
				return leftExpression.in(values)

			case "IS":
				return leftExpression.is(rightExpression)

			case "ISNOT", "!IS":
				return leftExpression.isNot(rightExpression)

			case "ISNULL", "ISNULLORMISSING":
				return leftExpression.isNullOrMissing()

			case "LT", "<":
				return leftExpression.lessThan(try buildExpression(valueString, defaultCommand: "DOUBLE", defaultSource: defaultSource))

			case "LTE", "<=":
				return leftExpression.lessThanOrEqualTo(try buildExpression(valueString, defaultCommand: "DOUBLE", defaultSource: defaultSource))

			case "LIKE":
				return leftExpression.like(rightExpression)

			case "NOTEQUALTO", "!":
				return leftExpression.notEqualTo(rightExpression)

			case "NOTNULL", "NOTNULLORMISSING", "!ISNULL":
				return leftExpression.notNullOrMissing()

			case "REGEX":
				return leftExpression.regex(rightExpression)

			default: // "EQUALTO"
				return leftExpression.equalTo(rightExpression)
			}
		}


		// ---- Basic Expression ---------------------------
		static func buildExpression(_ expressionString: String, defaultCommand: String = "STRING", defaultSource: String? = nil) throws -> ExpressionProtocol {

			// Command
			let (newExpressionString, _command) = parseCommand(expressionString)
			let commandParts = (_command ?? "").split(separator: "/", omittingEmptySubsequences: false)
			let command = commandParts.count > 0 && commandParts[0].count > 0 ? String(commandParts[0]) : defaultCommand
			switch command.uppercased() {

			case "ALL":
				return Expression.all()

			case "ABS":
				return Function.abs(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "ACOS":
				return Function.acos(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "ADD", "+":
				let addend = commandParts.count > 1 ? Double(commandParts[1]) : nil
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				if addend != nil {
					return expressionB.add(Expression.double(addend!))
				}
				return expressionB

			case "ARRAY":
				let jsObject = try parseJSON(newExpressionString) as? [Any]
				return Expression.array(jsObject)

			case "ASIN":
				return Function.asin(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "ATAN":
				return Function.atan(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			//	case "ATAN2": // x/y // How to handle inputs? Make this a comparator instead of a command?
			//		return Function.atan2(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource), )

			case "AVERAGE", "AVG":
				return Function.avg(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "BOOLEAN", "BOOL":
				let bool = newExpressionString.lowercased() == "true"
				return Expression.boolean(bool)

			case "CEIL":
				return Function.ceil(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "COS":
				return Function.cos(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "COUNT":
				return Function.count(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			//	case "DATE":
			//		// TODO: Date Stuff
			//		return Expression.date(Date?)
			//		break

			case "DEGREES":
				return Function.degrees(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "DIVIDE":
				let divisor = commandParts.count > 1 ? Double(commandParts[1]) : nil
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				if divisor != nil {
					return expressionB.divide(Expression.double(divisor!))
				}
				return expressionB

			case "DOUBLE":
				let value = Double(newExpressionString)
				return (value != nil ? Expression.double(value!) : Expression.value(nil))

			case "E":
				return Function.e()

			case "EXP":
				return Function.exp(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "FLOAT":
				let value = Float(newExpressionString)
				return (value != nil ? Expression.float(value!) : Expression.value(nil))

			case "FLOOR":
				return Function.floor(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "INTEGER", "INT":
				let value = Int(newExpressionString)
				return (value != nil ? Expression.int(value!) : Expression.value(nil))

			case "INTEGER64", "INT64":
				let value = Int64(newExpressionString)
				return (value != nil ? Expression.int64(value!) : Expression.value(nil))

			case "JSON, DICTIONARY":
				let jsObject = try parseJSON(newExpressionString) as! NSDictionary
				return Expression.value(jsObject)

			case "LENGTH":
				return Function.length(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "LENGTH[]", "ARRAY_LENGTH":
				return ArrayFunction.length(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "LN":
				return Function.ln(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "LOG":
				return Function.log(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "LOWER":
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				return Function.lower(expressionB)

			case "LTRIM":
				return Function.ltrim(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "MAX":
				return Function.max(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "MIN":
				return Function.min(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "META":
				var expressionB : ExpressionProtocol = Meta.id;
				let (propNameB, sourceB, _) = parseProperty(newExpressionString)

				switch propNameB {
					case "id": expressionB = Meta.id
					case "expiration": expressionB = Meta.expiration
					case "revisionID": expressionB = Meta.revisionID
					case "sequence": expressionB = Meta.sequence
					case "isDeleted": expressionB = Meta.isDeleted
					default: break
				}
				if sourceB != nil || defaultSource != nil {
					expressionB = (expressionB as! MetaExpressionProtocol).from(sourceB ?? defaultSource!)
				}
				return expressionB

			case "MODULO":
				let divisor = commandParts.count > 1 ? Double(commandParts[1]) : nil
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				if divisor != nil {
					return expressionB.modulo(Expression.double(divisor!))
				}
				return expressionB

			case "MULTIPLY":
				let multiplicand = commandParts.count > 1 ? Double(commandParts[1]) : nil
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				if multiplicand != nil {
					return expressionB.multiply(Expression.double(multiplicand!))
				}
				return expressionB

			case "NEGATED":
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				return Expression.negated(expressionB)

			case "NOT":
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				return Expression.not(expressionB)

			case "PARAMETER", "PARAM":
				return Expression.parameter(newExpressionString)

			case "PI":
				return Function.pi()

			case "POWER": // base/exponent (Accepts Int for exponent, but Function.power can accept any Expresion for exponent (make comparator in-addition-to/instead-of command?))
				let exponent = commandParts.count > 1 ? Int(commandParts[1]) ?? 2 : 2
				return Function.power(base: try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource), exponent: Expression.int(exponent))

			case "PROPERTY", "PROP":
				let (propNameB, sourceB, _) = parseProperty(newExpressionString)
				if propNameB.lowercased() == "id" {
					return try buildExpression("META:id", defaultSource: sourceB ?? defaultSource)
				}
				if sourceB != nil || defaultSource != nil {
					return Expression.property(propNameB).from(sourceB ?? defaultSource!)
				}
				return Expression.property(propNameB)

			case "RADIANS", "RAD":
				return Function.radians(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "ROUND":
				let digits = commandParts.count > 1 ? Int(commandParts[1]) : nil
				if digits != nil && digits! > -1 {
					return Function.round(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource), digits: Expression.int(digits!))
				}
				return Function.round(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "RTRIM":
				return Function.rtrim(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "SIGN":
				return Function.sign(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "SIN":
				return Function.sin(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "SQRT":
				return Function.sqrt(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "STRING":
				return Expression.string(newExpressionString)

			case "SUBTRACT", "-":
				let subtrahend = commandParts.count > 1 ? Double(commandParts[1]) : nil
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				if subtrahend != nil {
					return expressionB.subtract(Expression.double(subtrahend!))
				}
				return expressionB

			case "SUM":
				return Function.sum(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "TAN":
				return Function.tan(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "TRIM":
				return Function.trim(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "TRUNCATE", "TRUNC": // digits
				return Function.trunc(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "UPPER":
				let expressionB = try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource)
				return Function.upper(expressionB)


			// ---- Date Functions -------------------------------
			case "STRINGTOMILLIS":
				return Function.stringToMillis(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "STRINGTOUTC":
				return Function.stringToUTC(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "MILLISTOSTRING":
				return Function.millisToString(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))

			case "MILLISTOUTC":
				return Function.millisToUTC(try buildExpression(newExpressionString, defaultCommand: defaultCommand, defaultSource: defaultSource))


			default: // No Command
				return Expression.string(newExpressionString)
			}
		}

	
		// -------------------------------------------------------------------------------------------
		// ---- Parse Expressions --------------------------------------------------------------------

		// ---- Parse Command ------------------------------
		static func parseCommand(_ expressionString: String) -> (String, String?) {

			return splitByDelimiter(expressionString, delimiter: ":")
		}

		static func parseProperty(_ keyString: String, sourceNames: [String] = []) -> (String, String?, String?) {

			let (expression, alias) = parseAlias(keyString)
			let (prop, source) = splitByDelimiter(expression, delimiter: "*")
			// Allow for "source.prop.subprop.etc" instead of "source*prop.subprop.etc". Not fully implemented.
			// if source == nil && sourceNames.count > 0 {
			// 	let expresionParts = expression.split(separator: ".")
			// 	if expresionParts.count > 1 && sourceNames.contains(String(expresionParts[0])) {
			// 		source = String(expresionParts[0])
			// 		prop = expresionParts.dropFirst(1).joined(separator: ".")
			// 	}
			//}
			return (prop, source, alias)
		}

		// ---- Parse Alias --------------------------------
		static func parseAlias(_ expressionString: String) -> (String, String?) {

			var expressionParts = expressionString.split(separator: " ", omittingEmptySubsequences: true)
			if expressionParts.count == 3 && expressionParts[1].uppercased() == "AS" {
				return (String(expressionParts[0]), String(expressionParts[2])) // source, alias
			}
			expressionParts = expressionString.split(separator: "=", maxSplits: 1)
			if expressionParts.count == 2 {
				return (String(expressionParts[0]), String(expressionParts[1])) // source, alias
			}
			return (expressionString, nil); // source, alias
		}

		// ---- Parse JSON ---------------------------------
		static func parseJSON(_ jsonString: String) throws -> Any {

			let data = Data(jsonString.utf8)
			return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
		}

		// ---- Parse Comparator ---------------------------
		static func parseComparator(_ expression: String) -> (String, String?) {

			let expressionParts = expression.split(separator: "(", maxSplits: 1)
			var comparator: String? = nil, newExpression = expression
			if expressionParts.count > 1 && expressionParts[1].count > 0 && expressionParts[1].suffix(1) == ")" {
				comparator = String(expressionParts[0])
				newExpression = String(expressionParts[1].prefix(expressionParts[1].count - 1))
			}
			return (newExpression, comparator)
		}

		// ---- Split By Delimiter -------------------------
		static func splitByDelimiter(_ expressionString: String, delimiter: String.Element, maxSplits: Int = 1, omittingEmptySubsequences: Bool = false) -> (String, String?) {

			let expressionParts = expressionString.split(separator: delimiter, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
			var partA = expressionString, partB : String? = nil
			if expressionParts.count > 1 {
				partB = String(expressionParts[0]);
				partA = String(expressionParts[1])
			}
			return (partA, partB)
		}
	  
	}
  
}

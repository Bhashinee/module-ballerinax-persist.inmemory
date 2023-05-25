// Copyright (c) 2023 WSO2 LLC. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
import ballerina/persist;

public isolated client class InMemoryClient {

    private final string[] & readonly keyFields;
    private final (isolated function (string[]) returns stream<record {}, persist:Error?>) & readonly query;
    private final (isolated function (anydata) returns record {}|persist:NotFoundError) & readonly queryOne;
    private final (map<(isolated function (record {}, string[]) returns record {}[]) & readonly> & readonly) associationsMethods;

    public isolated function init(TableMetadata & readonly metadata) returns persist:Error? {
        self.keyFields = metadata.keyFields;
        self.query = metadata.query;
        self.queryOne = metadata.queryOne;
        self.associationsMethods = metadata.associationsMethods;
    }

    public isolated function runReadQuery(string[] fields = []) returns stream<record {}, persist:Error?> {
        return self.query(self.addKeyFields(fields));
    }

    public isolated function runReadByKeyQuery(typedesc<record {}> rowType, anydata key, string[] fields = [], string[] include = [], typedesc<record {}>[] typeDescriptions = []) returns record {}|persist:Error {
        record {} 'object = check self.queryOne(key);

        'object = filterRecord('object, self.addKeyFields(fields));
        check self.getManyRelations('object, fields, include, typeDescriptions);
        self.removeUnwantedFields('object, fields);

        do {
            return check 'object.cloneWithType(rowType);
        } on fail error e {
            return <persist:Error>e;
        }
    }

    public isolated function getManyRelations(record {} 'object, string[] fields, string[] include, typedesc<record {}>[] typeDescriptions) returns persist:Error? {
        foreach int i in 0 ..< include.length() {
            string entity = include[i];
            string[] relationFields = from string 'field in fields
                where 'field.startsWith(entity + "[].")
                select 'field.substring(entity.length() + 3, 'field.length());

            if relationFields.length() is 0 {
                continue;
            }

            isolated function (record {}, string[]) returns record {}[] associationsMethod = self.associationsMethods.get(entity);
            record {}[] relations = associationsMethod('object, relationFields);
            'object[entity] = relations;
        }
    }

    public isolated function getKey(anydata|record {} 'object) returns anydata|record {} {
        record {} keyRecord = {};

        string[] keyFields = self.keyFields;

        if keyFields.length() == 1 && 'object is record {} {
            return 'object[keyFields[0]];
        }

        if 'object is record {} {
            foreach string key in keyFields {
                keyRecord[key] = 'object[key];
            }
        } else {
            keyRecord[keyFields[0]] = 'object;
        }
        return keyRecord;
    }

    public isolated function getKeyFields() returns string[] {
        return self.keyFields;
    }

    public isolated function addKeyFields(string[] fields) returns string[] {
        string[] updatedFields = fields.clone();

        foreach string key in self.keyFields {
            if updatedFields.indexOf(key) is () {
                updatedFields.push(key);
            }
        }
        return updatedFields;
    }

    private isolated function removeUnwantedFields(record {} 'object, string[] fields) {
        string[] keyFields = self.keyFields;

        foreach string keyField in keyFields {
            if fields.indexOf(keyField) is () {
                _ = 'object.remove(keyField);
            }
        }
    }

}

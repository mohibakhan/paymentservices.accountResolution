    public async Task<string?> UpdateLedgerItemStatus(string ledgerId, string entryId, string status)
    {
        string partitionKeyValue = ledgerId;
        string query = $"SELECT * FROM c WHERE c.id='{entryId}'";

        QueryDefinition queryDefinition = new QueryDefinition(query);
        FeedIterator<dynamic> queryResultSetIterator = _entryContainer.GetItemQueryIterator<dynamic>(
            queryDefinition,
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(partitionKeyValue) }
        );

        while (queryResultSetIterator.HasMoreResults)
        {
            FeedResponse<dynamic> currentResultSet = await queryResultSetIterator.ReadNextAsync();
            TransactionalBatch batch = _entryContainer.CreateTransactionalBatch(new PartitionKey(partitionKeyValue));

            foreach (var item in currentResultSet)
            {
                string id = item.id;
                List<PatchOperation> operations = new List<PatchOperation>()
                {
                     { PatchOperation.Set("/status", status) },
                     { PatchOperation.Set("/updatedAt", DateTime.UtcNow) }
                };

                batch.PatchItem(id, operations);
            }

            using TransactionalBatchResponse batchResponse = await batch.ExecuteAsync();
            if (batchResponse.IsSuccessStatusCode)
            {
                return ($"LedgerEntry status updated to {status}.");
            }
        }

        return ("Status not Updated");
    }

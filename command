Address = src.Address is null ? null : new Address
+                {
+                    City = src.Address.City,
+                    CountryISOCode = src.Address.CountryISOCode,
+                    PostalCode = src.Address.PostalCode,
+                    StateCode = src.Address.StateCode,
+                    AddressLines = src.Address.AddressLines
+                },

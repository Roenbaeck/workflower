-- Snowflake test: AND/OR logical operators
SELECT SISULATE(
    '$/ foreach item in items where item.price > 50 and item.category == "electronics"\n-- AND test: $item.name$ (Price: $item.price$, Category: $item.category$)\n$/ endfor\n\n$/ foreach item in items where item.category == "books" or item.category == "media"\n-- OR test: $item.name$ (Category: $item.category$)\n$/ endfor\n\n$/ foreach item in items\n$/ if item.price > 40 and item.stock > 0\n-- IF AND test: $item.name$ available\n$/ endif\n$/ endfor',
    '{"items": [{"name": "Laptop", "price": 999, "category": "electronics", "stock": 10}, {"name": "Mouse", "price": 25, "category": "electronics", "stock": 50}, {"name": "Book", "price": 15, "category": "books", "stock": 100}, {"name": "DVD", "price": 20, "category": "media", "stock": 0}, {"name": "Keyboard", "price": 75, "category": "electronics", "stock": 3}]}'
) AS test_and_or;

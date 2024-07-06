def maximize_loot(capacity, items):
    items_with_ratio = [(item[0], item[1], item[1] / item[0]) for item in items]
    items_with_ratio.sort(key=lambda x: x[2], reverse=True)
    loot = []
    current_weight = 0
    current_value = 0

    for weight, value, ratio in items_with_ratio:
        if current_weight + weight <= capacity:
            loot.append((weight, value))
            current_weight += weight
            current_value += value

    return current_weight, current_value


capacity = int(input())
count_items = int(input())
items = [list(map(int, input().split(','))) for i in range(count_items)]
print(maximize_loot(capacity, items))

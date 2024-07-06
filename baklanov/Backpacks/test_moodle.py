"""The template for a "write a program" question type that accepts answers
    in C, C++, Java or Python3 according to the value in the language select
    dropdown menu.
"""
import random
import subprocess
import re
student_answer = """{{ STUDENT_ANSWER | e('py') }}"""
language = """{{ ANSWER_LANGUAGE | e('py') }}""".lower()
language_extension_map = {'c':'c', 'cpp':'cpp', 'java':'java', 'python3':'py'}

if language not in language_extension_map.keys():
    raise Exception('Error in question. Unknown/unexpected language ({})'.format(language))

if language == 'java':
    # Need to determine public class name in order to name output file. Sigh.
    # The best I can be bothered to do is to use a regular expression match.
    match = re.search(r'public\s+class\s+([_a-zA-Z][_a-zA-Z0-9]*)', student_answer, re.DOTALL | re.MULTILINE)
    if match is None:
        raise Exception("Unable to determine class name. Does the file include 'public class name'?")
    classname = match.group(1)
    filename = classname + '.java'
else:
    filename = '__tester__.' + language_extension_map[language]

# Write the student code to a file

with open(filename, "w") as src:
    print(student_answer, file=src)

# Compile C, C++ and Java
if language == 'c':
    cflags = "-std=c99 -Wall -Werror"
    return_code = subprocess.call("gcc {0} -o __tester__ __tester__.c".format(cflags).split())
    if return_code != 0:
        raise Exception("** Compilation failed. Testing aborted **")
    exec_command = ["./__tester__"]
elif language == 'cpp':
    cppflags = "-Wall -Werror"
    return_code = subprocess.call("g++ {0} -o __tester__ __tester__.cpp".format(cppflags).split())
    if return_code != 0:
        raise Exception("** Compilation failed. Testing aborted **")
    exec_command = ["./__tester__"]
elif language == 'java':
    return_code = subprocess.call(['javac', "-J-Xss64m", "-J-Xmx4g", filename])
    if return_code != 0:
        raise Exception("** Compilation failed. Testing aborted **")
    exec_command = ["java", "-Xss16m", "-Xmx500m", classname]
else: # Python doesn't need a compile phase
    exec_command = ["python3", "./__tester__.py"]

# Now run the code. Since this is a per-test template,
# stdin is already set up for the stdin text specified in the test case,
# so we can run the compiled program directly.

def check(reply, clue):
    return str(reply).strip() == str(clue).strip()

def generate(key = 0):
    if key == 0:
        dataset = ['30\n5\n3, 10\n5, 15\n7, 20\n8, 25\n10, 30', '40\n6\n4, 12\n6, 20\n9, 28\n12, 35\n15, 40\n18, 45', '50\n10\n2, 10\n4, 15\n6, 20\n8, 25\n10, 30\n12, 35\n14, 40\n16, 45\n18, 50\n20, 55\n22, 60\n24, 65\n26, 70\n28, 75\n30, 80\n32, 85\n34, 90\n36, 95\n38, 100\n40, 105\n42, 110\n44, 115\n46, 120\n48, 125\n50, 130\n52, 135\n54, 140\n56, 145\n58, 150\n60, 155']
    else:
        dataset = []
        for i in range(3):
            capacity = random.randint(200, 500)
            num_items = random.randint(3, 100)
            items = []
            for _ in range(num_items):
                weight = random.randint(1, 50)
                value = random.randint(10, 140)
                items.append((weight, value))
            dataset_i = f"{capacity}\n{num_items}\n"
            for weight, value in items:
                dataset_i += f"{weight}, {value}\n"
            dataset.append(dataset_i)
    return dataset





def maximize_loot_check(dataset):
    lines = dataset.split('\n')
    capacity, num_items = int(lines[0]), int(lines[1])
    items = []
    for line in lines[2:]:
        if line != '':
            weight, value = map(int, line.split(', '))
            items.append((weight, value))
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

tests = generate()
len_tests = len(tests)
incorrect_count = 0
correct_count = 0
COUNT_OPEN_TESTS = 3
try:
    for test in tests:
        stud_output = subprocess.check_output(exec_command, input=test, universal_newlines=True)
        expected_output = maximize_loot_check(test)
        if str(expected_output).strip() != stud_output.strip():
            incorrect_count += 1
            if incorrect_count < 3:
                result = f'Test: {test}\n'
                result += f'Your answer: {stud_output}\n'
                result += f'Correct: {expected_output}\n'
                print(result)
        else:
            correct_count += 1
except subprocess.CalledProcessError as e:
    if e.returncode > 0:
        if e.output:
            print(e.output)
    else:
        if e.output:
            print(e.output, file=sys.stderr)
        if e.returncode < 0:
            print("Task failed with signal", -e.returncode, file=sys.stderr)
        print("** Further testing aborted **", file=sys.stderr)

if correct_count == len_tests:
    print('OK')
else:
    print('Failed')
"""Turns the university's exam timetable PDF into the app's exam data.

Usage: python tool/exam_timetable.py <timetable.pdf> <term> <kind> <out.json>
e.g.   python tool/exam_timetable.py "Timetable for 2026 Fall Midterm Exam.pdf" "Fall 2026" midterm \
           assets/exams/2026-fall-midterm.json

The PDF is one grid (the bot in D:\\coding\\inha_timetable reads the same
layout): a title row ("Mid Term Mon.,26.10-30.10"), a header row of rooms
("A202" .. "B210"), a "Places" row with their seats, then one row per slot:
the weekday (merged across its rows, so only on one of them), the time
("09:30- 11:00"), the slot ("M-1 90") and one cell per room with the course
sitting there. One course usually spans several rooms in a slot.

The output keeps each cell's text as printed and lists the rooms it fills,
one entry per slot and cell. Reading a cell (the course, "(UK)", groups,
a teacher, minutes) is the app's job (lib/data/exams.dart), where it is
tested. Dates come from the title's day range and the term's year; the
weekday from the slot code (M, T, W, Th, F). Review the result against the
PDF before committing it: it is the only check that this is the sheet.
"""
import datetime
import json
import re
import sys

import pdfplumber

PDF, TERM, KIND, OUT = sys.argv[1:5]

SLOT = re.compile(r'^(M|T|W|Th|F)\s*-\s*(\d+)')
TIME = re.compile(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$')
DAYS = {'M': 0, 'T': 1, 'W': 2, 'Th': 3, 'F': 4}


def text(cell):
    """A cell's text on one line: the PDF wraps long names."""
    return ' '.join((cell or '').split())


def room(name):
    return name.replace(' ', '')  # "B304 (C)" -> "B304(C)"


def same_cell(cell):
    """The key that groups a course's rooms: "Math for IT(26-01/03..." and
    "Math for IT (26-01/03..." are the same sitting."""
    return re.sub(r'(\S)\(', r'\1 (', cell)


def first_monday(title, year):
    m = re.search(r'(\d{1,2})\.(\d{1,2})\s*-\s*(\d{1,2})\.(\d{1,2})', title)
    if not m:
        sys.exit(f'No day range like "26.10-30.10" in the title {title!r}')
    first = datetime.date(year, int(m[2]), int(m[1]))
    if first.weekday() != 0:
        sys.exit(f'{first} is not a Monday; check the title {title!r} and the term')
    return first


def main():
    year = int(re.search(r'\d{4}', TERM)[0])
    with pdfplumber.open(PDF) as pdf:
        rows = [[text(c) for c in row] for page in pdf.pages for t in page.extract_tables() for row in t]

    title = next(c for row in rows for c in row if c)
    header = next(i for i, row in enumerate(rows) if 'Slots' in row)
    slot_col = rows[header].index('Slots') + 1  # "Slots" heads the time and the slot column
    time_col = slot_col - 1
    rooms = [(i, room(c)) for i, c in enumerate(rows[header]) if i > slot_col and c]
    places = rows[header + 1] if 'Places' in rows[header + 1] else [''] * len(rows[header])
    monday = first_monday(title, year)

    exams = []
    for row in rows[header + 1:]:
        slot = SLOT.match(row[slot_col])
        if not slot:
            continue
        code = f'{slot[1]}-{slot[2]}'
        time = TIME.match(row[time_col].replace(' ', ''))
        if not time:
            sys.exit(f'Slot {code} has no time range: {row[time_col]!r}')
        day = monday + datetime.timedelta(days=DAYS[slot[1]])
        sittings = {}
        for i, name in rooms:
            if row[i]:
                sittings.setdefault(same_cell(row[i]), (row[i], []))[1].append(name)
        for cell, names in sittings.values():
            exams.append({
                'slot': code,
                'date': day.isoformat(),
                'start': f'{int(time[1]):02}:{time[2]}',
                'end': f'{int(time[3]):02}:{time[4]}',
                'cell': cell,
                'rooms': names,
            })

    out = {
        'format': 1,
        'id': f'{year}-{TERM.split()[0].lower()}-{KIND}',
        'kind': KIND,
        'term': TERM,
        'title': title,
        'source': PDF.replace('\\', '/').split('/')[-1],
        # Set to true once the university has said which room each student sits in.
        'roomsAssigned': False,
        'seats': {name: int(places[i]) if places[i].isdigit() else None for i, name in rooms},
        'exams': exams,
    }
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'{OUT}: {len(exams)} sittings in {len({e["slot"] for e in exams})} slots, {len(rooms)} rooms')


main()

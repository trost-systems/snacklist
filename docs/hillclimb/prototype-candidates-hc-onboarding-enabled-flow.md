# Prototype candidates from the onboarding climb (job 461)

Ideas the climb found that would change what the steps look like or how they read. None is built.
Each needs a prototype round before anyone picks it.

## P1: Weiter on „Was fehlt gerade?“ counts the typed item

**Problem.** Since job 461, „Weiter“ adds what is still in the field. The button still reads
„Weiter“ (or „Weiter mit 2 Artikeln“) without that item, so the count is one short at the moment
of the tap (`docs/screenshots/461/04-need-typed.png`: „Hafermilch“ typed, the button says
„Weiter“; the invite step then says „1 Artikel wartet schon auf der Liste.“).

**Idea.** Count a non-empty field in the label: „Weiter mit 1 Artikel“ as soon as a letter is
typed. Or show the typed text as a ghost chip under „Auf deiner Liste“.

**Compare.** The label alone, the ghost chip, and today's label. Measure whether test users press
+ before Weiter, and whether a changing label while typing distracts.

## P2: The name counter counts what the server counts

**Problem.** The name fields stop at 80 code points (job 461), but the counter under them counts
characters. A name with a family emoji stops at „75/80“.

**Idea.** A counter in code points, or no counter until 60 and then „noch 20“.

**Compare.** Today's counter, a code-point counter, a late remaining count. The case is rare: a long
name with emoji of several code points.

## P3: Typed text survives Zurück on „Was fehlt gerade?“

**Problem.** Text typed in the field and not added is lost on Zurück (Weiter keeps it now). It is
not a required answer, so the climb left it.

**Idea.** Keep the field's text in the draft, as the household name is, and put it back on return.

**Compare.** This is behaviour only, with no visible change. Decide whether Zurück should keep the
text or add it as an item, then build it as a simple fix.

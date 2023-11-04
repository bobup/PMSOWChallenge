/* filter.js */
/* This code is the original work of George Martsoukos (2022). 
** See https://webdesign.tutsplus.com/protect-html-email-links--cms-41203t */

const links = document.querySelectorAll("[data-part1][data-part2][data-part3]");
for (const link of links) {
  const attrs = link.dataset;
  link.setAttribute(
	"href",
	"mailto:${attrs.part1}@${attrs.part2}.${attrs.part3}?subject=${attrs.subject}"
  );
  link.textContent = "${attrs.part1}@${attrs.part2}.${attrs.part3}";
}

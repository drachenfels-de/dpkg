/*
 * libdpkg - Debian packaging suite library routines
 * showpkg.c - customizable package listing
 *
 * Copyright © 2001 Wichert Akkerman <wakkerma@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/parsedump.h>

typedef enum {
	invalid,
	string,
	field,
} itemtype_t;

struct lstitem {
	itemtype_t type;
	size_t width;
	int pad;
	char *data;
	struct lstitem *next;
};


static struct lstitem *
alloclstitem(void)
{
	struct lstitem *buf;

	buf = m_malloc(sizeof(struct lstitem));
	buf->type = invalid;
	buf->next = NULL;
	buf->data = NULL;
	buf->width = 0;
	buf->pad = 0;

	return buf;
}

static int
parsefield(struct lstitem *cur, const char *fmt, const char *fmtend)
{
	int len;
	const char *ws;

	len = fmtend - fmt + 1;

	ws = memchr(fmt, ';', len);
	if (ws) {
		char *endptr;
		long w;

		w = strtol(ws + 1, &endptr, 0);
		if (endptr[0] != '}') {
			fprintf(stderr,
			        _("invalid character `%c' in field width\n"),
			       *endptr);
			return 0;
		}

		if (w < 0) {
			cur->pad = 1;
			cur->width = (size_t)-w;
		} else
			cur->width = (size_t)w;

		len = ws - fmt;
	}

	cur->type = field;
	cur->data = m_malloc(len + 1);
	memcpy(cur->data, fmt, len);
	cur->data[len] = '\0';

	return 1;
}

static int
parsestring(struct lstitem *cur, const char *fmt, const char *fmtend)
{
	int len;
	char *write;

	len = fmtend - fmt + 1;

	cur->type = string;
	write = cur->data = m_malloc(len + 1);
	while (fmt <= fmtend) {
		if (*fmt == '\\') {
			fmt++;
			switch (*fmt) {
			case 'n':
				*write = '\n';
				break;
			case 't':
				*write = '\t';
				break;
			case 'r':
				*write = '\r';
				break;
			case '\\':
			default:
				*write = *fmt;
				break;
			}
		} else
			*write = *fmt;
		write++;
		fmt++;
	}
	*write = '\0';

	return 1;
}

void
freeformat(struct lstitem *head)
{
	struct lstitem *next;

	while (head) {
		next = head->next;
		free(head->data);
		free(head);
		head = next;
	}
}

struct lstitem *
parseformat(const char *fmt)
{
	struct lstitem *head;
	struct lstitem *cur;
	const char *fmtend;

	head = cur = NULL;

	while (*fmt) {
		if (cur)
			cur = cur->next = alloclstitem();
		else
			head = cur = alloclstitem();

		if (fmt[0] == '$' && fmt[1] == '{') {
			fmtend = strchr(fmt, '}');
			if (!fmtend) {
				fprintf(stderr,
				      _("Closing brace missing in format\n"));
				freeformat(head);
				return NULL;
			}

			if (!parsefield(cur, fmt + 2, fmtend - 1)) {
				freeformat(head);
				return NULL;
			}
			fmt = fmtend + 1;
		} else {
			fmtend = fmt;
			do {
				fmtend += 1;
				fmtend = strchr(fmtend, '$');
			} while (fmtend && fmtend[1] != '{');

			if (!fmtend)
				fmtend = fmt + strlen(fmt);

			if (!parsestring(cur, fmt, fmtend - 1)) {
				freeformat(head);
				return NULL;
			}
			fmt = fmtend;
		}
	}

	return head;
}

void
show1package(const struct lstitem *head,
             struct pkginfo *pkg, struct pkginfoperfile *pif)
{
	struct varbuf vb = VARBUF_INIT, fb = VARBUF_INIT, wb = VARBUF_INIT;

	/* Make sure we have package info available, even if it's all empty. */
	if (!pif->valid)
		blankpackageperfile(pif);

	while (head) {
		int ok;
		char fmt[16];

		ok = 0;

		if (head->width > 0)
			snprintf(fmt, 16, "%%%s%zds",
			         ((head->pad) ? "-" : ""), head->width);
		else
			strcpy(fmt, "%s");

		if (head->type == string) {
			varbufprintf(&fb, fmt, head->data);
			ok = 1;
		} else if (head->type == field) {
			const struct fieldinfo *fip;

			for (fip = fieldinfos; fip->name; fip++)
				if (strcasecmp(head->data, fip->name) == 0) {
					fip->wcall(&wb, pkg, pif, 0, fip);

					varbufaddc(&wb, '\0');
					varbufprintf(&fb, fmt, wb.buf);
					varbufreset(&wb);
					ok = 1;
					break;
				}

			if (!fip->name && pif->valid) {
				const struct arbitraryfield *afp;

				for (afp = pif->arbs; afp; afp = afp->next)
					if (strcasecmp(head->data, afp->name) == 0) {
						varbufprintf(&fb, fmt, afp->value);
						ok = 1;
						break;
					}
			}
		}

		if (ok) {
			size_t len = strlen(fb.buf);
			if ((head->width > 0) && (len > head->width))
				len = head->width;
			varbufaddbuf(&vb, fb.buf, len);
		}

		varbufreset(&fb);
		head = head->next;
	}

	if (vb.buf) {
		varbufaddc(&vb, '\0');
		fputs(vb.buf, stdout);
	}

	varbuf_destroy(&wb);
	varbuf_destroy(&fb);
	varbuf_destroy(&vb);
}


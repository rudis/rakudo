my class X::Buf::AsStr          { ... }
my class X::Buf::Pack           { ... }
my class X::Buf::Pack::NonASCII { ... }
my class X::Cannot::Empty       { ... }
my class X::Cannot::Lazy        { ... }
my class X::Experimental        { ... }
my class X::TypeCheck           { ... }

my role Blob[::T = uint8] does Positional[T] does Stringy is repr('VMArray') is array_type(T) {
    multi method new(Blob:) { nqp::create(self) }
    multi method new(Blob: Blob:D $blob) {
        nqp::splice(nqp::create(self),$blob,0,0)
    }
    multi method new(Blob: int @values) {
        nqp::splice(nqp::create(self),@values,0,0)
    }
    multi method new(Blob: @values) {
        @values.is-lazy
          ?? fail X::Cannot::Lazy.new(:action<new>,:what(self.^name))
          !! self!push-list("initializ",nqp::create(self),@values)
    }
    multi method new(Blob: *@values) { self.new(@values) }

    proto method allocate(|) { * }
    multi method allocate(Blob:U: Int $elements) {
        nqp::setelems(nqp::create(self),$elements)
    }
    multi method allocate(Blob:U: Int $elements, int $value) {
        my int $elems = $elements;
        my $blob     := nqp::setelems(nqp::create(self),$elems);
        my int $i     = -1;
        nqp::bindpos_i($blob,$i,$value) while nqp::islt_i($i = $i + 1,$elems);
        $blob;
    }
    multi method allocate(Blob:U: Int $elements, Int \value) {
        my int $value = value;
        self.allocate($elements,$value)
    }
    multi method allocate(Blob:U: Int $elements, Mu $got) {
        self!fail-typecheck('allocate',$got)
    }
    multi method allocate(Blob:U: Int $elements, int @values) {
        self!initialize(nqp::setelems(nqp::create(self),$elements),0,@values)
    }
    multi method allocate(Blob:U: Int $elements, Blob:D $blob) {
        self!initialize(nqp::setelems(nqp::create(self),$elements),0,$blob)
    }
    multi method allocate(Blob:U: Int $elements, @values) {
        self!initialize(
          nqp::setelems(nqp::create(self),$elements),0,Blob.new(@values))
    }

    multi method EXISTS-POS(Blob:D: int \pos) {
        nqp::p6bool(
          nqp::islt_i(pos,nqp::elems(self)) && nqp::isge_i(pos,0)
        );
    }
    multi method EXISTS-POS(Blob:D: Int:D \pos) {
        pos < nqp::elems(self) && pos >= 0;
    }

    multi method AT-POS(Blob:D: int \pos) {
        fail X::OutOfRange.new(
          :what($*INDEX // 'Index'),
          :got(pos),
          :range("0..{nqp::elems(self)-1}")
        ) if nqp::isge_i(pos,nqp::elems(self)) || nqp::islt_i(pos,0);
        nqp::atpos_i(self, pos);
    }
    multi method AT-POS(Blob:D: Int:D \pos) {
        my int $pos = nqp::unbox_i(pos);
        fail X::OutOfRange.new(
          :what($*INDEX // 'Index'),
          :got(pos),
          :range("0..{nqp::elems(self)-1}")
        ) if nqp::isge_i($pos,nqp::elems(self)) || nqp::islt_i($pos,0);
        nqp::atpos_i(self,$pos);
    }

    multi method Bool(Blob:D:) {
        nqp::p6bool(nqp::elems(self));
    }

    method elems(Blob:D:) {
        nqp::p6box_i(nqp::elems(self));
    }
    method bytes(Blob:D:) {
        ceiling(self.elems * ::T.^nativesize / 8);
    }
    method chars(Blob:D:)       { X::Buf::AsStr.new(method => 'chars').throw }
    multi method Str(Blob:D:)   { X::Buf::AsStr.new(method => 'Str'  ).throw }
    multi method Stringy(Blob:D:) { X::Buf::AsStr.new(method => 'Stringy' ).throw }

    method Numeric(Blob:D:) { self.elems }
    method Int(Blob:D:)     { self.elems }

    method decode(Blob:D: $encoding = 'utf-8') {
        nqp::p6box_s(
          nqp::decode(self, Rakudo::Internals.NORMALIZE_ENCODING($encoding)))
    }

    multi method list(Blob:D:) {
        Seq.new(class :: does Rakudo::Internals::BlobbyIterator {
            method pull-one() is raw {
                nqp::islt_i($!i = $!i + 1,$!elems)
                  ?? nqp::atpos_i($!blob,$!i)
                  !! IterationEnd
            }
        }.new(self))
    }

    multi method gist(Blob:D:) {
        self.^name ~ ':0x<' ~ self.list.fmt('%02x', ' ') ~ '>'
    }
    multi method perl(Blob:D:) {
        self.^name ~ '.new(' ~ self.list.join(', ') ~ ')';
    }

    method subbuf(Blob:D: $from, $length?) {

        my int $elems = nqp::elems(self);
        X::OutOfRange.new(
          what => "Len element to subbuf",
          got  => $length,
          range => "0..$elems",
        ).fail if $length.DEFINITE && $length < 0;

        my int $pos;
        my int $todo;
        if nqp::istype($from,Range) {
            ($pos,my int $max) = $from.int-bounds;
            $todo = $max - $pos + 1;
        }
        else {
            $pos = nqp::istype($from, Callable) ?? $from($elems) !! $from.Int;
            $todo = $length.DEFINITE
              ?? $length.Int min $elems - $pos
              !! $elems - $pos;
        }

        X::OutOfRange.new(
          what    => 'From argument to subbuf',
          got     => $from.gist,
          range   => "0..$elems",
          comment => "use *{$pos} if you want to index relative to the end",
        ).fail if $pos < 0;
        X::OutOfRange.new(
          what => 'From argument to subbuf',
          got  => $from.gist,
          range => "0..$elems",
        ).fail if $pos > $elems;

        my $subbuf := nqp::create(self);
        if $todo {
            nqp::setelems($subbuf, $todo);
            my int $i = -1;
            $pos = $pos - 1;
            nqp::bindpos_i($subbuf,$i,nqp::atpos_i(self,($pos = $pos + 1)))
              while ($i = $i + 1) < $todo;
        }
        $subbuf
    }

    method COMPARE(Blob:D: Blob:D \other) {
        my $other := nqp::decont(other);
        my int $elems = nqp::elems(self);
        if nqp::cmp_i($elems,nqp::elems($other)) -> $diff {
            $diff
        }
        else {
            my int $i = -1;
            return nqp::cmp_i(nqp::atpos_i(self,$i),nqp::atpos_i($other,$i))
              if nqp::cmp_i(nqp::atpos_i(self,$i),nqp::atpos_i($other,$i))
              while nqp::islt_i($i = $i + 1,$elems);
            0
        }
    }

    method SAME(Blob:D: Blob:D \other) {
        my $other := nqp::decont(other);
        my int $elems = nqp::elems(self);
        return False unless nqp::iseq_i($elems,nqp::elems($other));

        my int $i = -1;
        return False
          unless nqp::iseq_i(nqp::atpos_i(self,$i),nqp::atpos_i($other,$i))
          while nqp::islt_i($i = $i + 1,$elems);

        True
    }

    proto method unpack(|) { * }
    multi method unpack(Blob:D: Str:D $template) {
        nqp::isnull(nqp::getlexcaller('EXPERIMENTAL-PACK')) and X::Experimental.new(
            feature => "the 'unpack' method",
            use     => "pack"
        ).throw;
        self.unpack($template.comb(/<[a..zA..Z]>[\d+|'*']?/))
    }
    multi method unpack(Blob:D: @template) {
        nqp::isnull(nqp::getlexcaller('EXPERIMENTAL-PACK')) and X::Experimental.new(
            feature => "the 'unpack' method",
            use     => "pack"
        ).throw;
        my @bytes = self.list;
        my @fields;
        for @template -> $unit {
            my $directive = substr($unit,0,1);
            my $amount    = substr($unit,1);
            my $pa = $amount eq ''  ?? 1            !!
                     $amount eq '*' ?? @bytes.elems !! +$amount;

            given $directive {
                when 'a' | 'A' | 'Z' {
                    @fields.push: @bytes.splice(0, $pa).map(&chr).join;
                }
                when 'H' {
                    my str $hexstring = '';
                    for ^$pa {
                        my $byte = shift @bytes;
                        $hexstring ~= ($byte +> 4).fmt('%x')
                                    ~ ($byte % 16).fmt('%x');
                    }
                    @fields.push($hexstring);
                }
                when 'x' {
                    splice @bytes, 0, $pa;
                }
                when 'C' {
                    @fields.append: @bytes.splice(0, $pa);
                }
                when 'S' | 'v' {
                    for ^$pa {
                        last if @bytes.elems < 2;
                        @fields.append: shift(@bytes)
                                    + (shift(@bytes) +< 0x08);
                    }
                }
                when 'L' | 'V' {
                    for ^$pa {
                        last if @bytes.elems < 4;
                        @fields.append: shift(@bytes)
                                    + (shift(@bytes) +< 0x08)
                                    + (shift(@bytes) +< 0x10)
                                    + (shift(@bytes) +< 0x18);
                    }
                }
                when 'n' {
                    for ^$pa {
                        last if @bytes.elems < 2;
                        @fields.append: (shift(@bytes) +< 0x08)
                                    + shift(@bytes);
                    }
                }
                when 'N' {
                    for ^$pa {
                        last if @bytes.elems < 4;
                        @fields.append: (shift(@bytes) +< 0x18)
                                    + (shift(@bytes) +< 0x10)
                                    + (shift(@bytes) +< 0x08)
                                    + shift(@bytes);
                    }
                }
                X::Buf::Pack.new(:$directive).throw;
            }
        }

        return |@fields;
    }

    # XXX: the pack.t spectest file seems to require this method
    # not sure if it should be changed to list there...
    method contents(Blob:D:) { self.list }

    method encoding() { Any }

    method !push-list(\action,\to,\from) {
        if nqp::istype(from,List) {
            my Mu $from  := nqp::getattr(from,List,'$!reified');
            my int $elems = nqp::elems($from);
            my int $j     = nqp::elems(to);
            nqp::setelems(to, $j + $elems);  # presize for efficiency
            my int $i = -1;
            my $got;
            nqp::istype(($got := nqp::atpos($from,$i)),Int)
              ?? nqp::bindpos_i(to,$j++,$got)
              !! self!fail-typecheck-element(action,$i,$got).throw
              while nqp::islt_i($i = $i + 1,$elems);
        }
        else {
            my $iter := from.iterator;
            my int $i = 0;
            my $got;
            until ($got := $iter.pull-one) =:= IterationEnd {
                nqp::istype($got,Int)
                  ?? nqp::push_i(to,$got)
                  !! self!fail-typecheck-element(action,$i,$got).throw;
                $i = $i + 1;
            }
        }
        to
    }
    method !unshift-list(\action,\to,\from) {
        if nqp::istype(from,List) {
            my Mu $from := nqp::getattr(from,List,'$!reified');
            my int $i    = nqp::elems($from);
            nqp::istype((my $got := nqp::atpos($from,$i)),Int)
              ?? nqp::unshift_i(to,$got)
              !! self!fail-typecheck-element(action,$i,$got).throw
              while nqp::isge_i($i = $i - 1,0);
            to
        }
        else {
            nqp::splice(to,self!push-list(action,nqp::create(self),from),0,0)
        }
    }
    method !initialize(\to,\at,\from) {
        if nqp::elems(from) -> int $values { # something to init with
            my int $elems = nqp::elems(to) - $values;
            my int $i     = at - $values;
            nqp::splice(to,from,$i,$values)
              while nqp::isle_i($i = $i + $values,$elems);

            if nqp::isgt_i($i,$elems) {  # something left to init
                $i     = $i - 1;         # went one too far
                $elems = $elems + $values;
                my int $j = -1;
                nqp::bindpos_i(to,$i,nqp::atpos_i(from,$j = ($j + 1) % $values))
                  while nqp::islt_i($i = $i + 1,$elems);
            }
        }
        to
    }
    method !fail-typecheck-element(\action,\i,\got) {
        self!fail-typecheck(action ~ "ing element #" ~ i,got);
    }
    method !fail-typecheck($action,$got) {
        fail X::TypeCheck.new(
          operation => $action ~ " to " ~ self.^name,
          got       => $got,
          expected  => T,
        );
    }
}

constant blob8 = Blob[uint8];
constant blob16 = Blob[uint16];
constant blob32 = Blob[uint32];
constant blob64 = Blob[uint64];

my class utf8 does Blob[uint8] is repr('VMArray') {
    method decode(utf8:D: $encoding = 'utf-8') {
        my $enc = Rakudo::Internals.NORMALIZE_ENCODING($encoding);
        die "Can not decode a utf-8 buffer as if it were $encoding"
            unless $enc eq 'utf8';
        nqp::p6box_s(nqp::decode(self, 'utf8'))
    }
    method encoding() { 'utf-8' }
    multi method Str(utf8:D:) { self.decode }
    multi method Stringy(utf8:D:) { self.decode }
}

my class utf16 does Blob[uint16] is repr('VMArray') {
    method decode(utf16:D: $encoding = 'utf-16') {
        my $enc = Rakudo::Internals.NORMALIZE_ENCODING($encoding);
        die "Can not decode a utf-16 buffer as if it were $encoding"
            unless $enc eq 'utf16';
        nqp::p6box_s(nqp::decode(self, 'utf16'))
    }
    method encoding() { 'utf-16' }
    multi method Str(utf16:D:) { self.decode }
    multi method Stringy(utf16:D:) { self.decode }
}

my class utf32 does Blob[uint32] is repr('VMArray') {
    method decode(utf32:D: $encoding = 'utf-32') {
        my $enc = Rakudo::Internals.NORMALIZE_ENCODING($encoding);
        die "Can not decode a utf-32 buffer as if it were $encoding"
            unless $enc eq 'utf32';
        nqp::p6box_s(nqp::decode(self, 'utf32'))
    }
    method encoding() { 'utf-32' }
    multi method Str(utf32:D:) { self.decode }
    multi method Stringy(utf32:D:) { self.decode }
}

my role Buf[::T = uint8] does Blob[T] is repr('VMArray') is array_type(T) {
    multi method AT-POS(Buf:D: int \pos) is raw {
        fail X::OutOfRange.new(
          :what($*INDEX // 'Index'),:got(pos),:range<0..Inf>)
            if nqp::islt_i(pos,0);
        nqp::atposref_i(self, pos);
    }
    multi method AT-POS(Buf:D: Int:D \pos) is raw {
        my int $pos = nqp::unbox_i(pos);
        fail X::OutOfRange.new(
          :what($*INDEX // 'Index'),:got(pos),:range<0..Inf>)
            if nqp::islt_i($pos,0);
        nqp::atposref_i(self,$pos);
    }

    multi method ASSIGN-POS(Buf:D: int \pos, Mu \assignee) {
        fail X::OutOfRange.new(
          :what($*INDEX // 'Index'),:got(pos),:range<0..Inf>)
            if nqp::islt_i(pos,0);
        nqp::bindpos_i(self,\pos,assignee)
    }
    multi method ASSIGN-POS(Buf:D: Int:D \pos, Mu \assignee) {
        my int $pos = nqp::unbox_i(pos);
        fail X::OutOfRange.new(
          :what($*INDEX // 'Index'),:got(pos),:range<0..Inf>)
            if nqp::islt_i($pos,0);
        nqp::bindpos_i(self,$pos,assignee)
    }

    multi method list(Buf:D:) {
        Seq.new(class :: does Rakudo::Internals::BlobbyIterator {
            method pull-one() is raw {
                nqp::islt_i($!i = $!i + 1,$!elems)
                  ?? nqp::atposref_i($!blob,$!i)
                  !! IterationEnd
            }
        }.new(self))
    }

    multi method pop(Buf:D:) {
        nqp::elems(self)
          ?? nqp::pop_i(self)
          !! fail X::Cannot::Empty.new(:action<pop>, :what(self.^name))
    }
    multi method shift(Buf:D:) {
        nqp::elems(self)
          ?? nqp::shift_i(self)
          !! fail X::Cannot::Empty.new(:action<shift>, :what(self.^name))
    }

    method reallocate(Buf:D: Int $elements) { nqp::setelems(self,$elements) }

    multi method splice(Buf:D: int $got, Int $offset = 0, $size = Whatever) {
        self!splice-native($got,$offset,$size)
    }
    multi method splice(Buf:D: Int $got, Int $offset = 0, $size = Whatever) {
        self!splice-native($got,$offset,$size)
    }
    multi method splice(Buf:D: Mu $got, Int $offset = 0, $size = Whatever) {
        self!fail-typecheck('splice',$got)
    }
    multi method splice(Buf:D: Buf:D $buf, Int $offset = 0, $size = Whatever) {
        self!splice-native($buf,$offset,$size)
    }
    multi method splice(Buf:D: int @values, Int $offset = 0, $size = Whatever) {
        self!splice-native(@values,$offset,$size)
    }
    multi method splice(Buf:D: @values, Int $offset = 0, $size = Whatever) {
        self!splice-native(
          self!push-list("splic",nqp::create(self),@values),$offset,$size)
    }

    method !splice-native(Buf:D: \x, int $offset, $size) {
        my int $remove = nqp::istype($size,Whatever)
          ?? nqp::elems(self) - $offset
          !! nqp::istype($size,Int)
            ?? $size
            !! $size.Int;
        my $result := $remove
          ?? self.subbuf($offset,$remove)  # until something smarter
          !! nqp::create(self);
        nqp::splice(self,nqp::islist(x) ?? x !! nqp::list_i(x),$offset,$remove);
        $result
    }

    multi method push(Buf:D: int $got) { nqp::push_i(self,$got); self }
    multi method push(Buf:D: Int $got) { nqp::push_i(self,$got); self }
    multi method push(Buf:D: Mu $got) { self!fail-typecheck('push',$got) }
    multi method push(Buf:D: Buf:D $buf) {
        nqp::splice(self,$buf,nqp::elems(self),0)
    }
    multi method push(Buf:D: int @values) {
        nqp::splice(self,@values,nqp::elems(self),0)
    }
    multi method push(Buf:D:  @values) { self!pend(@values,'push') }
    multi method push(Buf:D: *@values) { self!pend(@values,'push') }

    multi method append(Buf:D: int $got) { nqp::push_i(self,$got); self }
    multi method append(Buf:D: Int $got) { nqp::push_i(self,$got); self }
    multi method append(Buf:D: Mu $got) { self!fail-typecheck('append',$got) }
    multi method append(Buf:D: Buf:D $buf) {
        nqp::splice(self,$buf,nqp::elems(self),0)
    }
    multi method append(Buf:D: int @values) {
        nqp::splice(self,@values,nqp::elems(self),0)
    }
    multi method append(Buf:D:  @values) { self!pend(@values,'append') }
    multi method append(Buf:D: *@values) { self!pend(@values,'append') }

    multi method unshift(Buf:D: int $got) { nqp::unshift_i(self,$got); self }
    multi method unshift(Buf:D: Int $got) { nqp::unshift_i(self,$got); self }
    multi method unshift(Buf:D: Mu $got) { self!fail-typecheck('unshift',$got) }
    multi method unshift(Buf:D: Buf:D $buf)  { nqp::splice(self,$buf,0,0)    }
    multi method unshift(Buf:D: int @values) { nqp::splice(self,@values,0,0) }
    multi method unshift(Buf:D:  @values) { self!pend(@values,'unshift') }
    multi method unshift(Buf:D: *@values) { self!pend(@values,'unshift') }

    multi method prepend(Buf:D: int $got) { nqp::unshift_i(self,$got); self }
    multi method prepend(Buf:D: Int $got) { nqp::unshift_i(self,$got); self }
    multi method prepend(Buf:D: Mu $got) { self!fail-typecheck('prepend',$got) }
    multi method prepend(Buf:D: Buf:D $buf)  { nqp::splice(self,$buf,0,0)    }
    multi method prepend(Buf:D: int @values) { nqp::splice(self,@values,0,0) }
    multi method prepend(Buf:D:  @values) { self!pend(@values,'prepend') }
    multi method prepend(Buf:D: *@values) { self!pend(@values,'prepend') }

    method !pend(Buf:D: @values, $action) {
        @values.is-lazy
          ?? fail X::Cannot::Lazy.new(:$action,:what(self.^name))
          !! $action eq 'push' || $action eq 'append'
            ?? self!push-list($action,self,@values)
            !! self!unshift-list($action,self,@values)
    }
}

constant buf8 = Buf[uint8];
constant buf16 = Buf[uint16];
constant buf32 = Buf[uint32];
constant buf64 = Buf[uint64];

proto sub pack(|) { * }
multi sub pack(Str $template, *@items) {
    nqp::isnull(nqp::getlexcaller('EXPERIMENTAL-PACK')) and X::Experimental.new(
        feature => "the 'pack' function",
        use     => "pack"
    ).throw;
    pack($template.comb(/<[a..zA..Z]>[\d+|'*']?/), @items)
}

multi sub pack(@template, *@items) {
    nqp::isnull(nqp::getlexcaller('EXPERIMENTAL-PACK')) and X::Experimental.new(
        feature => "the 'pack' function",
        use     => "pack"
    ).throw;
    my @bytes;
    for @template -> $unit {
        my $directive = substr($unit,0,1);
        my $amount    = substr($unit,1);

        given $directive {
            when 'A' {
                my $ascii = shift @items // '';
                my $data = $ascii.ords.cache;
                if $amount eq '*' {
                    $amount = $data.elems;
                }
                if $amount eq '' {
                    $amount = 1;
                }
                for (@$data, 0x20 xx *).flat[^$amount] -> $byte {
                    X::Buf::Pack::NonASCII.new(:char($byte.chr)).throw if $byte > 0x7f;
                    @bytes.push: $byte;
                }
            }
            when 'a' {
                my $data = shift @items // Buf.new;
                $data.=encode if nqp::istype($data,Str);
                if $amount eq '*' {
                    $amount = $data.cache.elems;
                }
                if $amount eq '' {
                    $amount = 1;
                }
                for (@$data, 0 xx *).flat[^$amount] -> $byte {
                    @bytes.push: $byte;
                }
            }
            when 'H' {
                my $hexstring = shift @items // '';
                if $hexstring.chars % 2 {
                    $hexstring ~= '0';
                }
                @bytes.append: map { :16($_) }, $hexstring.comb(/../);
            }
            when 'x' {
                if $amount eq '*' {
                    $amount = 0;
                }
                elsif $amount eq '' {
                    $amount = 1;
                }
                @bytes.append: 0x00 xx $amount;
            }
            when 'C' {
                my $number = shift(@items);
                @bytes.push: $number % 0x100;
            }
            when 'S' | 'v' {
                my $number = shift(@items);
                @bytes.append: ($number, $number +> 0x08) >>%>> 0x100;
            }
            when 'L' | 'V' {
                my $number = shift(@items);
                @bytes.append: ($number, $number +> 0x08,
                              $number +> 0x10, $number +> 0x18) >>%>> 0x100;
            }
            when 'n' {
                my $number = shift(@items);
                @bytes.append: ($number +> 0x08, $number) >>%>> 0x100;
            }
            when 'N' {
                my $number = shift(@items);
                @bytes.append: ($number +> 0x18, $number +> 0x10,
                              $number +> 0x08, $number) >>%>> 0x100;
            }
            X::Buf::Pack.new(:$directive).throw;
        }
    }

    return Buf.new(@bytes);
}

multi sub infix:<~>(Blob:D $a, Blob:D $b) {
    my $res := ($a.WHAT === $b.WHAT ?? $a !! Buf).new;
    my $adc := nqp::decont($a);
    my $bdc := nqp::decont($b);
    my int $alen = nqp::elems($adc);
    my int $blen = nqp::elems($bdc);

    nqp::setelems($res, $alen + $blen);
    nqp::splice($res, $adc, 0, $alen);
    nqp::splice($res, $bdc, $alen, $blen);
}

multi sub prefix:<~^>(Blob:D $a) {
    $a ~~ Blob[int16] ?? $a.new($a.list.map: 0xFFFF - *) !!
    $a ~~ Blob[int32] ?? $a.new($a.list.map: 0xFFFFFFFF - *) !!
                         $a.new($a.list.map: 0xFF - *);
}

multi sub infix:<~&>(Blob:D \a, Blob:D \b) {
    my $a := nqp::decont(a);
    my $b := nqp::decont(b);
    my int $elemsa = nqp::elems($a);
    my int $elemsb = nqp::elems($b);
    my int $do  = $elemsa > $elemsb ?? $elemsb !! $elemsa;
    my int $max = $elemsa > $elemsb ?? $elemsa !! $elemsb;

    my $r := nqp::create($a);
    nqp::setelems($r,$max);

    my int $i = -1;
    nqp::bindpos_i($r,$i,
      nqp::bitand_i(nqp::atpos_i($a,$i),nqp::atpos_i($b,$i)))
      while nqp::islt_i($i = $i + 1,$do);

    $i = $i - 1;    # went one too far
    nqp::bindpos_i($r,$i,0) while nqp::islt_i($i = $i + 1,$max);

    $r
}

multi sub infix:<~|>(Blob:D \a, Blob:D \b) {
    my $a := nqp::decont(a);
    my $b := nqp::decont(b);
    my int $elemsa = nqp::elems($a);
    my int $elemsb = nqp::elems($b);
    my int $do  = $elemsa > $elemsb ?? $elemsb !! $elemsa;
    my int $max = $elemsa > $elemsb ?? $elemsa !! $elemsb;
    my $from   := $elemsa > $elemsb ?? $a      !! $b;

    my $r := nqp::create($a);
    nqp::setelems($r,$max);

    my int $i = -1;
    nqp::bindpos_i($r,$i,
      nqp::bitor_i(nqp::atpos_i($a,$i),nqp::atpos_i($b,$i)))
      while nqp::islt_i($i = $i + 1,$do);

    $i = $i - 1;    # went one too far
    nqp::bindpos_i($r,$i,nqp::atpos_i($from,$i))
      while nqp::islt_i($i = $i + 1,$max);

    $r
}

multi sub infix:<~^>(Blob:D \a, Blob:D \b) {
    my $a := nqp::decont(a);
    my $b := nqp::decont(b);
    my int $elemsa = nqp::elems($a);
    my int $elemsb = nqp::elems($b);
    my int $do  = $elemsa > $elemsb ?? $elemsb !! $elemsa;
    my int $max = $elemsa > $elemsb ?? $elemsa !! $elemsb;
    my $from   := $elemsa > $elemsb ?? $a      !! $b;

    my $r := nqp::create($a);
    nqp::setelems($r,$max);

    my int $i = -1;
    nqp::bindpos_i($r,$i,
      nqp::bitxor_i(nqp::atpos_i($a,$i),nqp::atpos_i($b,$i)))
      while nqp::islt_i($i = $i + 1,$do);

    $i = $i - 1;    # went one too far
    nqp::bindpos_i($r,$i,nqp::atpos_i($from,$i))
      while nqp::islt_i($i = $i + 1,$max);

    $r
}

multi sub infix:<eqv>(Blob:D \a, Blob:D \b) {
    a =:= b
      ?? True
      !! a.WHAT === b.WHAT
        ?? a.SAME(b)
        !! False
}

multi sub infix:<cmp>(Blob:D \a, Blob:D \b) { ORDER(a.COMPARE(b))     }
multi sub infix:<eq> (Blob:D \a, Blob:D \b) {   a =:= b || a.SAME(b)  }
multi sub infix:<ne> (Blob:D \a, Blob:D \b) { !(a =:= b || a.SAME(b)) }
multi sub infix:<lt> (Blob:D \a, Blob:D \b) { a.COMPARE(b) == -1      }
multi sub infix:<gt> (Blob:D \a, Blob:D \b) { a.COMPARE(b) ==  1      }
multi sub infix:<le> (Blob:D \a, Blob:D \b) { a.COMPARE(b) !=  1      }
multi sub infix:<ge> (Blob:D \a, Blob:D \b) { a.COMPARE(b) != -1      }

sub subbuf-rw(Buf:D \b, $from = 0, $elems = b.elems - $from) is rw {
    my Blob $subbuf = b.subbuf($from, $elems);
    Proxy.new(
        FETCH   => sub ($) { $subbuf },
        STORE   => sub ($, Blob:D $new) {
            nqp::splice(nqp::decont(b),nqp::decont($new),$from,$elems)
        }
    );
}

# vim: ft=perl6 expandtab sw=4

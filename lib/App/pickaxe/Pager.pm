package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::GUI::Pager', 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Getline 'getline';
use Mojo::Util 'decode', 'encode';
use Text::Wrap 'wrap';
use Mojo::Util 'html_unescape', 'tablify';

has helpbar => "q:Quit e:Edit /:find o:Open %:Preview D:Delete ?:help";

has 'config';
has 'index';

sub statusbar ($self) {
    my $base  = $self->api->base_url->clone->query( key => undef );
    my $page = $self->index->current_page->title;
    my $percent;
    if ( $self->nlines == 0 ) {
        $percent = '100';
    }
    else {
        $percent = int( $self->current_line / $self->nlines * 100 );
    }
    return "pickaxe: $base $title", sprintf( "--%3d%%", $percent );
}

sub next_item ( $self, $key ) {
    $self->index->next_item( $key );
}

sub prev_item ( $self, $key ) {
    $self->index->prev_item( $key );
}

sub edit_page ( $self, $key ) {
    $self->next::method($key);
}

sub render_text ( $self, $text ) {

    ## Move <pre> to it's own line
    $text =~ s/^(\S+)(<\/?pre>)/$1\n$2/gms;
    $text =~ s/(<\/?pre>)(\S+)$/$1\n$2/gms;

    ## Remove empty lists
    $text =~ s/^\s*[\*\#]\s*\n//gmsx;

    ## Unscape html entities
    $text = html_unescape($text);

    # Remove header ids
    $text =~ s/^h(\d)\(.*?\)\./h$1./gms;

    ## Collapse empty lines;
    $text =~ s/\n{3,}/\n\n\n/gs;

    my @table;
    my $pre_mode = 0;
    my @lines;
    for my $line ( split( "\n", $text ) ) {
        if ( $line =~ /<pre>/ ) {
            $pre_mode = 1;
        }
        elsif ( $line =~ /<\/pre>/ ) {
            $pre_mode = 0;
        }
        elsif ($pre_mode) {
            push @lines, "    " . $line;
        }
        elsif ( $line =~ /^\s*\|(.*)\|\s*$/ ) {
            push @table,
              [ map { s/_\.//; s/^\s*//; s/\s*$//; $_ } split( '\|', $1 ) ];
        }
        elsif (@table) {
            push @lines, split( "\n", tablify( \@table ) );
            undef @table;
            redo;
        }
        elsif ( $line =~ /^(\s*[\*\#]\s*)\S/ ) {
            push @lines, split( "\n", wrap( '', ' ' x length($1), $line ) );
        }
        elsif ( $line eq '' ) {
            push @lines, $line;
        }
        else {
            $line =~ /^(\s*)/;
            push @lines, split( "\n", wrap( $1, $1, $line ) );
        }
    }
    if (@table) {
        push @lines, split( "\n", tablify( \@table ) );
    }
    return @lines;
}

has 'old_page';

sub render ( $self ) {
    if ( $self->old_page ne $self->index->current_page ) {
        my $page = $self->index->current_page;
        $self->old_page($page); 
        $self->set_lines( $self->render_text( $page->text ));
    }
    $self->next::method;
}

sub run ($self) {
    my $page = $self->index->current_page;
    $self->old_page($page); 
    $self->set_lines( $self->render_text( $page->text ));
    $self->next::method( $self->config->{keybindings} );
}

1;

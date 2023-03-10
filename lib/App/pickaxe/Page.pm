package App::pickaxe::Page;
use Mojo::Base -base, -signatures;

use Text::Wrap 'wrap';
use Mojo::Util 'html_unescape', 'tablify';

has 'title';
has 'version';
has 'created_on';
has 'updated_on';
has 'parent';
has 'api';
has childs => sub { [] };

has extended => sub ($self) {
    my $version = $self->version;
    my $title   = $self->title;
    my $res =
      $self->api->get( "wiki/$title/$version.json", include => 'attachments' );
    if ( $res->is_success ) {
        my $page = $res->json->{wiki_page};
        $page->{text} =~ s/\r\n/\n/gs;
        $page->{attachments} =
          [ map { App::pickaxe::Page::Attachment->new($_) }
              @{ $page->{attachments} } ];
        return App::pickaxe::Page::Extended->new($page);
    }
    return App::pickaxe::Page::Extended->new;
};

sub parent_page ($self) {
    $self->parent
      ? $self->api->page( $self->parent->{title}, -1 )
      : undef;
}

sub level ($self) {
    my $i      = 0;
    my $parent = $self->parent;
    while ($parent) {
        $i++;
        $parent = $self->api->page( $parent, -1 )->parent;
    }
    return $i;
}

sub comments    { shift->extended->comments }
sub author      { shift->extended->author }
sub text        { shift->extended->text }
sub attachments { shift->extended->attachments }

has url => sub ($self) {
    my $url = $self->api->base_url->clone->path( "wiki/" . $self->title );
    $url->query( key => undef );
    return $url->to_string;
};

has rendered_text => sub ($self) {

    my $text = $self->text;

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
    $text =~ s/\r\n/\n/g;

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
    return join( "\n", @lines );

};

1;

package App::pickaxe::Page::Extended;
use Mojo::Base -base;
has [qw(comments author text attachments)];
1;

package App::pickaxe::Page::Attachment;
use Mojo::Base -base;
has [
    qw(filename filesize content_url content_type created_on author description id)
];
1;

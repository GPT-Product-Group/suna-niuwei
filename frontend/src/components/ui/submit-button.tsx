'use client';

import { useFormStatus } from 'react-dom';
import { type ComponentProps } from 'react';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription } from './alert';
import { AlertTriangle } from 'lucide-react';

type Props = Omit<ComponentProps<typeof Button>, 'formAction'> & {
  pendingText?: string;
  formAction: (formData: FormData) => Promise<any> | void;
  errorMessage?: string;
};

// Inner button that uses useFormStatus to detect parent form submission
function PendingButton({
  children,
  pendingText = 'Submitting...',
  formAction,
  ...props
}: Omit<ComponentProps<typeof Button>, 'formAction'> & {
  pendingText?: string;
  formAction: (formData: FormData) => Promise<any> | void;
}) {
  const { pending } = useFormStatus();

  return (
    <Button
      {...props}
      type="submit"
      aria-disabled={pending}
      disabled={props.disabled || pending}
      formAction={formAction}
    >
      {pending ? pendingText : children}
    </Button>
  );
}

export function SubmitButton({
  children,
  formAction,
  errorMessage,
  pendingText = 'Submitting...',
  ...props
}: Props) {
  return (
    <div className="flex flex-col gap-y-4 w-full">
      {Boolean(errorMessage) && (
        <Alert variant="destructive" className="w-full">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      )}
      <div>
        <PendingButton
          {...props}
          pendingText={pendingText}
          formAction={formAction}
        >
          {children}
        </PendingButton>
      </div>
    </div>
  );
}

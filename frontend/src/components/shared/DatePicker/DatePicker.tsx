import './DatePicker.scss';

interface DatePickerProps {
  label:    string;
  value:    string | null;
  onChange: (value: string | null) => void;
}

// A labelled date input.
// Controlled component — value always comes from props,
// changes are reported up via onChange. Same pattern as
// ng-model in AngularJS but explicit.

const DatePicker = ({ label, value, onChange }: DatePickerProps) => {
  return (
    <div className="date-picker">
      <label className="date-picker__label">{label}</label>
      <input
        className="date-picker__input"
        type="date"
        value={value ?? ''}
        onChange={e => onChange(e.target.value || null)}
      />
    </div>
  );
};

export default DatePicker;
